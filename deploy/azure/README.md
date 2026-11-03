# Azure Linux VM staging

These are staging artifacts, not a deployment. They create **one private Linux
VM**, OS and SQLite data managed disks encrypted at rest with platform-managed
keys, host encryption enabled, and a virtual network with all inbound traffic
denied by default. There is no public IP, service ingress, deployment workflow,
or production learner data. An operator may optionally set one approved
private CIDR to allow SSH only from that management network; the default is to
deny even SSH. The default Rust service exposes only `GET /health/ready`. Experimental pairing
and sync routes exist in code but are not mounted by default; sync additionally
requires the explicit legal-approval feature.

## Human-only prerequisites and approvals

Do not run a deployment command until a human has selected and approved:

- Azure tenant, subscription, resource group, and permitted staging region.
- A non-overlapping VNet/subnet CIDR and an exact Canonical Ubuntu 24.04 image
  version. The template does not default the address space or use a floating
  `latest` image.
- VM size, OS/data disk SKUs, data-disk capacity, and an Azure budget/cost
  alert. The VM size must support encryption at host.
- Private operator access (for example, an already-approved VPN or existing
  private management network). This template intentionally creates no public
  IP or paid Bastion/NAT resources. Use the optional SSH CIDR only for a
  dedicated private management range; leave it empty if no such path is
  approved.
- Azure Backup vault region/redundancy and policy, after confirming the
  OS-only/SQLite-disk-excluded policy described below is supported.
- An administrator SSH public key. Keep the corresponding private key outside
  this repository and Azure deployment logs.

Never put credentials, SSH private keys, learner data, or production settings
in a parameter file or source control. The template does not deploy itself,
create a resource group, provision access infrastructure, or choose pricing.

## Review and deploy manually

Install Azure CLI with Bicep support, authenticate to the approved tenant, and
select the approved subscription. The following PowerShell commands are
examples; replace each placeholder only after the human decisions above. Do
not use an unreviewed deployment or a public endpoint.

```powershell
$ResourceGroup = '<approved-existing-resource-group>'
$Location = '<approved-region>'
$VnetAddressPrefix = '<approved-non-overlapping-vnet-cidr>'
$SubnetAddressPrefix = '<approved-subnet-cidr-contained-in-vnet>'
$UbuntuImageVersion = '<approved-canonical-ubuntu-24.04-image-version>'
$VmName = 'learning-calculator-stage'
$AdminUsername = '<approved-linux-admin>'
$SshPublicKey = (Get-Content -Raw '<path-to-ssh-public-key>').Trim()
$VmSize = '<approved-encryption-at-host-capable-vm-size>'
$OsDiskSku = '<approved-os-disk-sku>'
$DataDiskSku = '<approved-data-disk-sku>'
$DataDiskSizeGiB = [int](Read-Host 'Approved data disk capacity in GiB')
$ManagementSourceAddressPrefix = Read-Host 'Approved private management CIDR, or empty for none'

az account show
az vm image list --location $Location --publisher Canonical `
  --offer ubuntu-24_04-lts --sku server --all --query "[].{version:version}" --output table
az deployment group what-if `
  --resource-group $ResourceGroup `
  --template-file .\deploy\azure\main.bicep `
  --parameters location=$Location vnetAddressPrefix=$VnetAddressPrefix `
    subnetAddressPrefix=$SubnetAddressPrefix ubuntuImageVersion=$UbuntuImageVersion `
    vmName=$VmName adminUsername=$AdminUsername `
    adminSshPublicKey=$SshPublicKey vmSize=$VmSize osDiskSku=$OsDiskSku `
    dataDiskSku=$DataDiskSku dataDiskSizeGiB=$DataDiskSizeGiB `
    managementSourceAddressPrefix=$ManagementSourceAddressPrefix
```

If no management CIDR is approved, omit the final
`managementSourceAddressPrefix=...` argument; the template then denies all
inbound traffic.

Review the `what-if` output with the resource owner. Only an authorized human
may then run this same command with `what-if` replaced by `create`. It creates
billable resources. If SSH is required, the supplied CIDR must be the approved
private management subnet, not a public workstation address; no service port
is opened. Delete staged resources through the
approved change process when no longer needed, after checking Azure Backup
recovery points and any retention hold.

## Configure the SQLite disk and service

Build `learning-calculator-service` for the VM's Linux architecture in a
controlled build environment. Transfer the reviewed binary to the VM over the
approved private channel, then install it at
`/opt/learning-calculator/bin/learning-calculator-service`. Never build from
unreviewed or untrusted source on the VM.

The attached managed disk is empty. Before formatting, verify the disk's LUN,
size, and Azure resource ID against the deployment output; formatting the wrong
device destroys data. On the new VM, identify the attached disk (normally
`/dev/disk/azure/scsi1/lun0`), format it once as ext4, mount it at
`/var/lib/learning-calculator`, and add its filesystem UUID to `/etc/fstab` with
`nofail,nodev,nosuid`. Do not put the database on the OS disk. Create a
`learning-calculator` system user/group and make the mounted directory
writable only by that account.

Install `learning-calculator.service` as
`/etc/systemd/system/learning-calculator.service`. Create
`/etc/learning-calculator/service.env`, owned by `root:learning-calculator`
with mode `0640`, containing only:

```ini
DATABASE_URL=sqlite:///var/lib/learning-calculator/service.db
BIND_ADDR=127.0.0.1:3000
RUST_LOG=info
```

Enable the service only after checking the mount and file permissions:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now learning-calculator
curl --fail http://127.0.0.1:3000/health/ready
```

This loopback-only service is not reachable outside the VM. Do not change
`BIND_ADDR`, add a service NSG rule, or add a public IP as part of staging.

## Backup, retention, and deletion policy

The separation between disks is intentional: the SQLite database belongs only
on the encrypted data disk. Configure automated Azure VM backups **for the OS
disk only**, with seven-day recovery-point retention. A human must create or
select an approved Recovery Services vault in the VM's region, choose its
redundancy and cost settings, and configure Azure VM backup using a policy with
daily backups and seven-day retention. In the VM's disk-selection settings,
explicitly select only the OS disk (selective disk backup) and exclude the
SQLite data disk. If selective OS-only backup is unavailable, do not enable VM
backup. Retain the change record and verify protected-disk selection and
recovery-point contents after the first backup. Azure Backup vault settings
and costs are human choices and are not provisioned by this template.

This policy is safe for the current no-learner-data staging service: OS backup
points contain no SQLite database, and all learner data is prohibited. Do not
create full-VM backups, snapshots, disk copies, exports, or backups that include
the data disk. Do not restore an OS recovery point over a database disk.
Because backups omit the database, they cannot recover SQLite data after
data-disk loss; this is deliberate until a deletion-safe production backup
design is approved.

The seven-day limit applies only to OS recovery points, not to learner data.
If any learner data is ever present in an unintended backup, stop data
collection, restrict access, notify the privacy/security owner, and follow the
incident and deletion process; do not treat normal expiry as satisfying a
guardian deletion request. The service implements per-entry 90-day expiry and
guardian-triggered live-database history erasure, but these operations do not
reach any database backup, snapshot, export, or recovery copy. Do not enable
database backups until a separately approved design enforces expiry and
guardian deletion across the live database **and every backup/recovery copy**,
with independently verified deletion completion and a retention bound that
does not extend the promised deletion.

The live database runs retention cleanup on startup and before API operations,
and the service purges expired data every minute while it is running. A
successful paired-device sync read/write, pairing-code creation, or completed
pairing, and a guardian-authenticated history erase update the profile's `last_activity_at` using
server UTC time. Requests without valid bearer authentication and local
calculations do not count; an authenticated request counts even if its payload
is later rejected. Expired history is never extended by profile activity. An
empty profile, its linked devices, and pairing metadata are deleted after 90
days without that activity. The HTTP erasure request requires the profile's
distinct guardian credential in the `X-Guardian-Authorization` header and
must be initiated only by the app's protected guardian controls. Ordinary
paired-device bearer credentials cannot erase history. Erasure records a
server-side timestamp and rejects later sync submissions whose history
timestamp is at or before that clear time, preventing ordinary stale retries
from restoring erased entries. Future client-supplied `recorded_at` values are
rejected; entry retention is anchored to the accepted recorded timestamp.

Guardian credentials are not minted through the API. Before production use, an
authorized operator must provision the SHA-256 hash directly in the profile
record through a trusted, access-controlled setup process and deliver the
high-entropy raw credential to the guardian through a separately verified
secure channel. No public or unauthenticated mint/reset endpoint exists. This
manual bootstrap and secret delivery procedure still requires an approved
operational runbook.

## Mandatory production gate

Cloud sync and production learner data remain **disabled** until qualified
U.S. legal/privacy review approves the parental-consent approach and the
production owner records that approval. A guardian toggle is not presumed
sufficient. This gate also requires verification of per-entry 90-day deletion
and guardian history erasure that preserves only the permitted profile shell,
plus a backup/restore design that cannot resurrect deleted history. No
deployment here is approval to launch, expose a public endpoint, or collect
learner data.
