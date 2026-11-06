# Slurm on Rocky Linux 9 for AI and HPC Workloads

**Complete instructor guide:** architecture, installation planning, configuration, CPU jobs, NVIDIA GPU jobs, accounting, Prometheus, Grafana, troubleshooting, and production-readiness.

**Lab scope**

> The reference architecture in Sections 2–3 describes a four-node example cluster: one controller/management node and three compute nodes. Section 7.2 provides the separate, validated two-node lab walkthrough. It uses Rocky Linux 9, Slurm, Munge, MariaDB, NVIDIA GPU resources, Prometheus, and Grafana. Replace example hostnames, IP addresses, resource counts, versions, and credentials with values validated for your environment.

## 1. What is Slurm?

Slurm (Simple Linux Utility for Resource Management) is an open-source workload manager and job scheduler used by High Performance Computing (HPC), AI/ML infrastructure, scientific computing, simulation, and GPU clusters.

Slurm manages shared compute resources and decides when and where jobs run. Users submit work rather than manually choosing a compute server.

Typical responsibilities:

1.  Job submission and queue management.
2.  CPU, memory, GPU, and other resource allocation.
3.  Scheduling based on availability, priority, partitions, accounts, and policy.
4.  Starting and monitoring tasks on compute nodes.
5.  Job completion, exit status, and usage accounting.
6.  Fair-share, Quality of Service (QOS), and resource limits.

Slurm is not Kubernetes. Kubernetes primarily orchestrates long-running containerized applications and services. Slurm is designed around scheduled jobs and resource allocations. Both can coexist in an AI platform.

## 2. Slurm architecture and components

``` mermaid
flowchart TB
    U[Users / Data Scientists] --> L[Login NodeSSH and Slurm CLI]
    L --> C[Controller: slurmctldQueue, scheduler, node state]
    C <--> D[slurmdbd + MariaDBAccounting, users, accounts, QOS]
    C --> W1[Worker 01slurmd · CPU/RAM]
    C --> W2[Worker 02slurmd · CPU/RAM/GPU]
    C --> W3[Worker 03slurmd · CPU/RAM/GPU]
    W1 --> M[Prometheus]
    W2 --> M
    W3 --> M
    M --> G[Grafana]
```

| Component     | Responsibility                                                         |
|:--------------|:-----------------------------------------------------------------------|
| Login node    | Users run Slurm client commands and prepare jobs                       |
| `slurmctld`   | Central controller; queue, scheduling, node state, resource allocation |
| `slurmd`      | Runs on every compute node; launches and monitors job tasks            |
| `slurmdbd`    | Accounting service between Slurm and the database                      |
| MariaDB/MySQL | Stores historical accounting data and associations                     |
| `slurmrestd`  | Optional REST API                                                      |
| Prometheus    | Scrapes and stores metrics                                             |
| Grafana       | Dashboards and visualization                                           |

The controller makes scheduling decisions. The worker daemon executes work. Accounting services provide historical records; they are not required for basic job execution.

## 3. Example lab infrastructure

| Hostname         |      Example IP | Role                                    | Example resources         |
|:-----------------|----------------:|:----------------------------------------|:--------------------------|
| `slurm-master`   | `192.168.10.10` | Controller + DB + monitoring (lab only) | 8 CPU, 32 GB RAM          |
| `slurm-worker01` | `192.168.10.11` | CPU compute                             | 32 CPU, 128 GB RAM        |
| `slurm-worker02` | `192.168.10.12` | GPU compute                             | 32 CPU, 128 GB RAM, 1 GPU |
| `slurm-worker03` | `192.168.10.13` | GPU compute                             | 32 CPU, 128 GB RAM, 1 GPU |

For production, separate the login, controller, database, and monitoring roles where practical. Consider a backup controller, shared storage, redundant networking, and tested recovery procedures.

## 4. End-to-end job workflow

1.  User connects to a login node using SSH.
2.  User submits a batch script using `sbatch`.
3.  The Slurm client sends the request to `slurmctld`.
4.  The job enters the queue.
5.  The scheduler evaluates partition, priority, resource requests, account/QOS policy, and node availability.
6.  The controller selects appropriate compute resources.
7.  The compute node’s `slurmd` launches the job.
8.  The workload executes using its allocated CPU, memory, GPU, and other resources.
9.  Slurm tracks job state, exit code, and resource usage.
10. Accounting records are sent through `slurmdbd` to MariaDB when accounting is configured.

| Command    | Purpose                                          |
|:-----------|:-------------------------------------------------|
| `sbatch`   | Submit a batch job                               |
| `srun`     | Run a command or job step within an allocation   |
| `salloc`   | Obtain an interactive allocation                 |
| `squeue`   | View pending and running jobs                    |
| `sinfo`    | View partitions and node states                  |
| `scancel`  | Cancel a job                                     |
| `scontrol` | Inspect and administer Slurm configuration/state |
| `sacct`    | Query historical job accounting                  |
| `sacctmgr` | Manage accounts, users, associations, and QOS    |
| `sstat`    | View supported statistics for running job steps  |
| `sdiag`    | Inspect scheduler statistics                     |
| `sreport`  | Generate accounting reports                      |

## 5. Rocky Linux 9 operating-system preparation

Perform the operating-system preparation on all nodes.

### 5.1 Update and install prerequisites

``` bash
sudo dnf update -y

sudo dnf install -y \
  epel-release chrony munge munge-libs munge-devel \
  gcc make pam-devel readline-devel perl openssl-devel \
  mariadb-server mariadb-devel git wget curl vim \
  tar bzip2 rsync
```

Package names and repository availability can vary by Slurm/OpenHPC release. Install the Slurm packages from one consistent, supported source rather than mixing unrelated repositories.

### 5.2 Set hostnames

Run the appropriate command on each machine:

``` bash
# Controller
sudo hostnamectl set-hostname slurm-master

# Compute node 1
sudo hostnamectl set-hostname slurm-worker01

# Compute node 2
sudo hostnamectl set-hostname slurm-worker02

# Compute node 3
sudo hostnamectl set-hostname slurm-worker03
```

### 5.3 Configure name resolution

Add to `/etc/hosts` on all nodes:

``` ini
192.168.10.10 slurm-master
192.168.10.11 slurm-worker01
192.168.10.12 slurm-worker02
192.168.10.13 slurm-worker03
```

Test:

``` bash
getent hosts slurm-master
getent hosts slurm-worker01
getent hosts slurm-worker02
getent hosts slurm-worker03
```

### 5.4 Synchronize time

On all nodes:

``` bash
sudo systemctl enable --now chronyd
chronyc tracking
chronyc sources -v
```

Configure all nodes to use consistent, trusted NTP sources.

### 5.5 Create consistent service accounts

Create the Slurm account with the same numeric UID and GID on all nodes. Confirm the chosen IDs are unused first.

``` bash
sudo groupadd -g 991 slurm

sudo useradd -u 991 -g slurm -M \
  -s /sbin/nologin slurm

id slurm
```

The `munge` service account must also be consistent and correctly configured on all nodes.

## 6. Munge authentication

Munge provides credential-based authentication between Slurm components.

Requirements:

- Munge installed on every cluster node.
- The same protected `munge.key` installed on every node.
- Correct ownership and permissions.
- Munge service running before Slurm daemons.

### 6.1 Generate the key on the controller

``` bash
sudo /usr/sbin/create-munge-key
sudo ls -l /etc/munge/munge.key
```

Generate the key once. Do not independently generate a different key on each worker.

### 6.2 Distribute securely

Transfer the key using a secure administrator-controlled method. Example:

``` bash
sudo scp /etc/munge/munge.key \
  root@slurm-worker01:/etc/munge/munge.key
sudo scp /etc/munge/munge.key \
  root@slurm-worker02:/etc/munge/munge.key
sudo scp /etc/munge/munge.key \
  root@slurm-worker03:/etc/munge/munge.key
```

On every node:

``` bash
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 0400 /etc/munge/munge.key
sudo systemctl enable --now munge
sudo systemctl status munge
```

### 6.3 Test Munge

On each node:

``` bash
munge -n | unmunge
```

Test across nodes:

``` bash
munge -n | ssh slurm-worker01 unmunge
```

Repeat for each worker. Successful decoding should report `STATUS: Success (0)`.

## 7. Install Slurm consistently

Choose one deployment method and pin the Slurm version.

**Option A — OpenHPC packages:** Use the OpenHPC release that explicitly supports your Rocky/EL9 environment and follow its installation procedure.

**Option B — Build Slurm RPMs:** Download a selected official Slurm release, build RPMs with the required plugins and dependencies, publish them in an internal repository, and install the same build on all applicable nodes.

Official references:

- Slurm documentation: https://slurm.schedmd.com/documentation.html
- Slurm quick start: https://slurm.schedmd.com/quickstart_admin.html
- OpenHPC: https://openhpc.community/

Required component placement:

| Component/package     |               Controller | Compute nodes |   Login node |
|:----------------------|-------------------------:|--------------:|-------------:|
| Slurm client commands |                      Yes |       Usually |          Yes |
| `slurmctld`           |                      Yes |            No |           No |
| `slurmd`              |                       No |           Yes |           No |
| `slurmdbd`            | Yes or dedicated DB host |            No |           No |
| Munge                 |                      Yes |           Yes |          Yes |
| GPU GRES/NVML support |              If GPU host |     GPU nodes | Not normally |

Do not assume the standard Rocky Linux repositories contain the Slurm release you need. Validate package availability and dependencies before deployment.

### 7.1 Create runtime directories

Controller:

``` bash
sudo mkdir -p /etc/slurm /var/log/slurm \
  /var/spool/slurmctld
sudo chown slurm:slurm /var/log/slurm /var/spool/slurmctld
```

Compute nodes:

``` bash
sudo mkdir -p /etc/slurm /var/log/slurm \
  /var/spool/slurmd
sudo chown slurm:slurm /var/log/slurm /var/spool/slurmd
```

### 7.2 Reproducible two-node installation (Rocky Linux 9.8 lab)

The following walkthrough documents the working two-node CPU lab used for the practical exercises in this guide. It is deliberately separate from the four-node example above. Use one topology consistently; do not combine the hostnames or node definitions from the two examples.

| Host     | Address          | Role                                                | Slurm daemon            |
|:---------|:-----------------|:----------------------------------------------------|:------------------------|
| `master` | `192.168.232.20` | Controller, login, SlurmDBD, MariaDB                | `slurmctld`, `slurmdbd` |
| `node01` | `192.168.232.21` | CPU compute node (4 CPUs, 15956 MiB configured RAM) | `slurmd`                |

Validated lab software: Rocky Linux 9.8 and Slurm `22.05.11-2.el9`. Package availability depends on enabled repositories. The commands below assume that the repository used by this lab provides these EL9 package names. Check the available version before installing, and install the same Slurm build on both nodes.

#### Step 1 — Prepare both nodes

Run on `master` and `node01`:

``` bash
sudo dnf update -y
sudo dnf install -y chrony munge munge-libs slurm
sudo systemctl enable --now chronyd

# Confirm host resolution and time synchronization
getent hosts master node01
chronyc tracking
```

Ensure `/etc/hosts` contains the same mappings on both hosts (or use working DNS):

``` text
192.168.232.20 master
192.168.232.21 node01
```

Check repository versions before installing role-specific packages:

``` bash
dnf list --showduplicates slurm slurm-slurmctld slurm-slurmd slurm-slurmdbd
```

#### Step 2 — Install the Slurm role packages

On `master`:

``` bash
sudo dnf install -y slurm-slurmctld slurm-slurmdbd
```

On `node01`:

``` bash
sudo dnf install -y slurm-slurmd
```

If the package manager proposes different Slurm versions across nodes, stop and resolve the repository/version mismatch before starting any Slurm daemon. Verify the installed packages:

``` bash
rpm -qa | grep -E '^(slurm|munge)' | sort
slurmctld -V 2>/dev/null || srun --version
```

The RPMs normally create the `slurm` service account. Confirm it exists on both hosts and has a consistent UID/GID; do not create a second account blindly:

``` bash
getent passwd slurm
getent group slurm
```

#### Step 3 — Configure MUNGE authentication

MUNGE must use the same key on every node. On `master`, generate the key once if it does not already exist:

``` bash
sudo /usr/sbin/create-munge-key
sudo systemctl enable --now munge
```

Copy the key securely to `node01` using an administrator-controlled channel. Do not place the key in Git, a tutorial repository, or a shell transcript:

``` bash
sudo scp /etc/munge/munge.key root@node01:/etc/munge/munge.key
```

On both nodes:

``` bash
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 0400 /etc/munge/munge.key
sudo systemctl enable --now munge
sudo systemctl status munge --no-pager
munge -n | unmunge
```

From `master`, test cross-node decoding:

``` bash
munge -n | ssh node01 unmunge
```

The decoded credential should report `STATUS: Success (0)`. Resolve MUNGE, time-sync, DNS, or SSH problems before proceeding.

#### Step 4 — Create Slurm runtime directories

On `master`:

``` bash
sudo install -d -o slurm -g slurm -m 0755 /etc/slurm /var/log/slurm
sudo install -d -o slurm -g slurm -m 0755 /var/spool/slurmctld
```

On `node01`:

``` bash
sudo install -d -o slurm -g slurm -m 0755 /etc/slurm /var/log/slurm
sudo install -d -o slurm -g slurm -m 0755 /var/spool/slurmd
```

#### Step 5 — Create the shared Slurm configuration

Create `/etc/slurm/slurm.conf` on `master`:

``` ini
ClusterName=hpc-lab
SlurmctldHost=master(192.168.232.20)

AuthType=auth/munge
CredType=cred/munge
SlurmUser=slurm

SlurmctldPort=6817
SlurmdPort=6818

StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd

SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log

SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

ProctrackType=proctrack/linuxproc

AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=master
AccountingStoragePort=6819
AccountingStorageUser=slurm

JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30

NodeName=node01 NodeAddr=192.168.232.21 CPUs=4 RealMemory=15956 State=UNKNOWN

PartitionName=compute Nodes=node01 Default=YES \
    MaxTime=01:00:00 \
    MaxNodes=1 \
    MaxCPUsPerNode=4 \
    State=UP
```

This is the configuration used for the CPU-only training cluster. The `CPUs` and `RealMemory` values must match resources Slurm can actually use on `node01`; leave memory for the operating system. GPU GRES is not configured in this two-node lab.

Copy the exact same file to the compute node and verify its checksum:

``` bash
sudo scp /etc/slurm/slurm.conf root@node01:/etc/slurm/slurm.conf
sha256sum /etc/slurm/slurm.conf
ssh root@node01 sha256sum /etc/slurm/slurm.conf
```

#### Step 6 — Configure MariaDB and SlurmDBD on the controller

On `master`:

``` bash
sudo dnf install -y mariadb-server
sudo systemctl enable --now mariadb
sudo systemctl status mariadb --no-pager
```

Create the accounting database and service account. Generate a unique secret locally and use the same value in MariaDB and `/etc/slurm/slurmdbd.conf`; never commit or publish it:

``` sql
CREATE DATABASE slurm_acct_db;
CREATE USER 'slurm'@'localhost' IDENTIFIED BY 'REPLACE_WITH_A_RANDOM_SECRET';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';
FLUSH PRIVILEGES;
```

Create `/etc/slurm/slurmdbd.conf` on `master` (replace the password locally; do not paste it into documentation):

``` ini
DbdHost=master
DbdPort=6819
SlurmUser=slurm
AuthType=auth/munge
DebugLevel=info
LogFile=/var/log/slurm/slurmdbd.log

StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=3306
StorageUser=slurm
StoragePass=REPLACE_WITH_THE_SAME_RANDOM_SECRET
StorageLoc=slurm_acct_db
```

Protect the file and prepare its log:

``` bash
sudo chown slurm:slurm /etc/slurm/slurmdbd.conf
sudo chmod 0600 /etc/slurm/slurmdbd.conf
sudo touch /var/log/slurm/slurmdbd.log
sudo chown slurm:slurm /var/log/slurm/slurmdbd.log
```

#### Step 7 — Configure the firewall

On `master`, permit Slurm controller and accounting traffic. Permit MariaDB only if required by the actual database topology; this example uses local MariaDB, so do not expose port 3306 unnecessarily.

``` bash
sudo firewall-cmd --permanent --add-port=6817/tcp
sudo firewall-cmd --permanent --add-port=6819/tcp
sudo firewall-cmd --reload
```

On `node01`:

``` bash
sudo firewall-cmd --permanent --add-port=6818/tcp
sudo firewall-cmd --reload
```

Restrict these services to trusted cluster networks in a production firewall policy. Confirm SELinux labels and policy rather than disabling SELinux as a troubleshooting shortcut.

#### Step 8 — Start services in order

On `master`, start MUNGE and the accounting database service before the controller:

``` bash
sudo systemctl enable --now munge mariadb
sudo systemctl enable --now slurmdbd
sudo systemctl status slurmdbd --no-pager
sudo journalctl -u slurmdbd -n 50 --no-pager
```

Register the cluster in accounting (run once):

``` bash
sudo sacctmgr -i add cluster hpc-lab
sudo sacctmgr list cluster
```

Then start the controller:

``` bash
sudo systemctl enable --now slurmctld
sudo systemctl status slurmctld --no-pager
```

On `node01`:

``` bash
sudo systemctl enable --now munge
sudo systemctl enable --now slurmd
sudo systemctl status slurmd --no-pager
```

#### Step 9 — Validate registration and submit a test job

From `master`:

``` bash
scontrol ping
sinfo -N -l
scontrol show node node01
srun --partition=compute --nodes=1 --ntasks=1 /bin/hostname
```

Expected hostname from the test job: `node01`. Submit a batch job:

``` bash
cat > hello-slurm.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=hello-slurm
#SBATCH --partition=compute
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:02:00
#SBATCH --output=hello-%j.out

echo "Job ID: ${SLURM_JOB_ID}"
echo "Host: $(hostname)"
echo "Started: $(date)"
sleep 5
echo "Completed: $(date)"
sleep 5
echo "Completed: $(date)"
EOF

sbatch hello-slurm.sh
squeue
```

After completion, inspect the output and accounting:

``` bash
cat hello-JOBID.out
sacct -j JOBID --format=JobID,JobName,Partition,State,Elapsed,AllocCPUS,ExitCode
```

Replace `JOBID` with the ID returned by `sbatch`. If accounting is not ready yet, basic `srun`/`sbatch` scheduling can still be tested while SlurmDBD is diagnosed; accounting commands require the accounting service and database to be healthy.

#### Step 10 — Useful service and troubleshooting commands

``` bash
systemctl status munge slurmctld slurmdbd
# Run on node01:
systemctl status munge slurmd

journalctl -u munge -n 100 --no-pager
journalctl -u slurmctld -n 100 --no-pager
journalctl -u slurmdbd -n 100 --no-pager
# Run on node01:
journalctl -u slurmd -n 100 --no-pager

scontrol show config
scontrol show node node01
sinfo
squeue
sacctmgr show cluster
sacct
```

Common first checks are: matching Slurm versions and `slurm.conf`, consistent MUNGE key and clock synchronization, correct service-account ownership of spool/log directories, DNS/`/etc/hosts`, firewall access, and the daemon-specific journal.

**Lab-specific note**

> installation above matches the two-node lab used for the completed hands-on exercises: `master` (`192.168.232.20`) and `node01` (`192.168.232.21`), Slurm `22.05.11-2.el9`, partition `compute`, and four configured CPUs on the compute node. The four-node CPU/GPU example in Sections 3 and 8–10 is a separate reference architecture, not the configuration to copy into this two-node lab.

## 8. Configure the Slurm controller

Create `/etc/slurm/slurm.conf` on the controller. This is an illustrative starting point; validate every parameter against the exact installed Slurm release and plugins.

``` ini
ClusterName=rocky-ai-hpc
SlurmctldHost=slurm-master

AuthType=auth/munge
CryptoType=crypto/munge
SlurmUser=slurm

SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log

StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd

SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup,task/affinity
JobAcctGatherType=jobacct_gather/cgroup

GresTypes=gpu

AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=slurm-master
AccountingStoragePort=6819

NodeName=slurm-worker01 CPUs=32 RealMemory=120000 State=UNKNOWN
NodeName=slurm-worker02 CPUs=32 RealMemory=120000 Gres=gpu:1 State=UNKNOWN
NodeName=slurm-worker03 CPUs=32 RealMemory=120000 Gres=gpu:1 State=UNKNOWN

PartitionName=cpu Nodes=slurm-worker[01-03] Default=YES State=UP
PartitionName=gpu Nodes=slurm-worker[02-03] State=UP

ReturnToService=2
SlurmctldTimeout=120
SlurmdTimeout=300
```

Configuration notes:

- Replace `CPUs=32` with the actual Slurm-visible CPU count on each node.
- `RealMemory=120000` is an example in MiB. Leave sufficient memory for the OS and system services.
- `Gres=gpu:1` assumes one schedulable GPU per GPU worker.
- Use matching node definitions and resource information on all nodes.
- Create the controller state directory and compute spool directories with the correct ownership.
- Do not enable accounting enforcement until accounts and associations have been created and verified.

Distribute the exact same `slurm.conf` to every node:

``` bash
sudo scp /etc/slurm/slurm.conf \
  root@slurm-worker01:/etc/slurm/slurm.conf
sudo scp /etc/slurm/slurm.conf \
  root@slurm-worker02:/etc/slurm/slurm.conf
sudo scp /etc/slurm/slurm.conf \
  root@slurm-worker03:/etc/slurm/slurm.conf
```

## 9. Configure cgroup resource controls

Rocky Linux 9 normally uses cgroup v2. Check:

``` bash
stat -fc %T /sys/fs/cgroup
```

Expected output:

``` text
cgroup2fs
```

Create `/etc/slurm/cgroup.conf` on the controller and compute nodes:

``` ini
CgroupPlugin=autodetect
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainDevices=yes
```

Check that the installed Slurm build supports the configured cgroup plugin and that the operating system’s systemd/cgroup configuration is compatible.

Cgroups help enforce resource boundaries for CPU, memory, and devices. They are important for preventing one job from consuming resources allocated to another.

## 10. Configure NVIDIA GPU GRES

Install a supported NVIDIA driver on GPU compute nodes. Confirm the driver and NVML library are available:

``` bash
nvidia-smi
nvidia-smi -L
nvidia-smi --query-gpu=name,memory.total,driver_version \
  --format=csv
```

Create `/etc/slurm/gres.conf` on each GPU worker:

``` ini
AutoDetect=nvml
```

For manually configured devices, use the correct device files and GPU indices for that host. Do not copy a guessed device mapping across different GPU models or MIG layouts.

Verify:

``` bash
sudo slurmd -G
```

Then inspect the controller’s node view:

``` bash
sinfo -N -o "%N %P %G %T"
scontrol show node slurm-worker02
```

GRES means Generic Resource Scheduling. It allows Slurm to allocate GPUs and other consumable resources to jobs.

**MIG note:** MIG configuration changes the visible GPU resource topology. Configure Slurm GRES according to the actual MIG instances and the GPU/MIG support of your Slurm and NVIDIA stack. Do not assume `Gres=gpu:1` represents every MIG instance.

## 11. Configure MariaDB and SlurmDBD accounting

Accounting stores historical jobs, usage, associations, accounts, and QOS information. It is separate from the basic controller/worker execution path.

### 11.1 Start MariaDB

On the database host (the controller in this lab):

``` bash
sudo systemctl enable --now mariadb
sudo systemctl status mariadb
sudo mariadb-secure-installation
```

### 11.2 Create the accounting database

Open MariaDB:

``` bash
sudo mariadb
```

Example SQL:

``` sql
CREATE DATABASE slurm_acct_db;

CREATE USER 'slurm'@'localhost'
IDENTIFIED BY 'REPLACE_WITH_A_LONG_RANDOM_SECRET';

GRANT ALL PRIVILEGES ON slurm_acct_db.*
TO 'slurm'@'localhost';

FLUSH PRIVILEGES;
EXIT;
```

If MariaDB is on a separate host, create a narrowly scoped database user for the SlurmDBD host rather than using `localhost` or a broad wildcard. Protect credentials and network access.

### 11.3 Create `/etc/slurm/slurmdbd.conf`

``` ini
AuthType=auth/munge

DbdHost=slurm-master
DbdPort=6819

SlurmUser=slurm
DebugLevel=info
LogFile=/var/log/slurm/slurmdbd.log

StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=3306
StorageUser=slurm
StoragePass=REPLACE_WITH_THE_SAME_DATABASE_SECRET
StorageLoc=slurm_acct_db
```

Set strict permissions:

``` bash
sudo chown slurm:slurm /etc/slurm/slurmdbd.conf
sudo chmod 600 /etc/slurm/slurmdbd.conf

sudo touch /var/log/slurm/slurmdbd.log
sudo chown slurm:slurm /var/log/slurm/slurmdbd.log
```

The database password must match the account created in MariaDB. Keep the file readable only by the required privileged service identity.

### 11.4 Configure accounting in `slurm.conf`

Ensure the controller configuration contains:

``` ini
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=slurm-master
AccountingStoragePort=6819
```

For initial bring-up, do not turn on strict association/limit enforcement before the account structure is ready.

### 11.5 Start services in a controlled order

On the controller:

``` bash
sudo systemctl enable --now mariadb
sudo systemctl enable --now munge
sudo systemctl enable --now slurmdbd
sudo systemctl status slurmdbd
```

Register the cluster using `sacctmgr` after SlurmDBD is reachable:

``` bash
sudo sacctmgr add cluster rocky-ai-hpc
sacctmgr list cluster
```

Then start the controller:

``` bash
sudo systemctl enable --now slurmctld
sudo systemctl status slurmctld
```

On each compute node:

``` bash
sudo systemctl enable --now munge
sudo systemctl enable --now slurmd
sudo systemctl status slurmd
```

Inspect logs:

``` bash
sudo journalctl -u slurmdbd -f
sudo journalctl -u slurmctld -f
sudo journalctl -u slurmd -f
```

## 12. Network and firewall

Default Slurm ports:

|     Port | Service                | Use                                     |
|---------:|:-----------------------|:----------------------------------------|
| TCP 6817 | `slurmctld`            | Controller communication                |
| TCP 6818 | `slurmd`               | Compute daemon communication            |
| TCP 6819 | `slurmdbd`             | Accounting daemon                       |
| TCP 3306 | MariaDB                | Database access; restrict to DB clients |
| TCP 9100 | Node Exporter          | Node metrics                            |
| TCP 9101 | Example Slurm exporter | Scheduler metrics                       |
| TCP 9400 | DCGM Exporter          | GPU metrics                             |
| TCP 9090 | Prometheus             | Metrics UI/API                          |
| TCP 3000 | Grafana                | Dashboard UI                            |

Example controller firewall rules:

``` bash
sudo firewall-cmd --permanent --add-port=6817/tcp
sudo firewall-cmd --permanent --add-port=6819/tcp
sudo firewall-cmd --permanent --add-port=3306/tcp
sudo firewall-cmd --reload
```

Example compute-node rules:

``` bash
sudo firewall-cmd --permanent --add-port=6818/tcp
sudo firewall-cmd --reload
```

These are illustrative port openings, not a complete security policy. Restrict source addresses to the management, compute, and monitoring networks. Open exporter and UI ports only where required. If using a separate database host, permit only the SlurmDBD host to reach MariaDB.

## 13. Verify the cluster

From the controller or login node:

``` bash
srun --version
sinfo
sinfo -N -l
scontrol show nodes
scontrol show partition
```

Check services:

``` bash
systemctl status munge
systemctl status slurmctld
systemctl status slurmdbd
```

On each compute node:

``` bash
systemctl status slurmd
```

If a node is not available, inspect its daemon logs and compare its local configuration, CPU count, memory, GRES, Munge key, and Slurm version with the controller.

## 14. Configure users and accounts

Create a training account:

``` bash
sudo sacctmgr add account ai-lab \
  Description="AI and HPC Training Account" \
  Organization=training
```

Create a user association:

``` bash
sudo sacctmgr add user USERNAME Account=ai-lab
```

Replace `USERNAME` with a real Linux user provisioned consistently on the login and compute nodes.

Inspect:

``` bash
sacctmgr show account
sacctmgr show user
sacctmgr show assoc
```

For a multi-user environment, configure accounts, associations, QOS, fair-share, job limits, and access controls deliberately. Test enforcement with non-administrator accounts.

## 15. Submit the first CPU job

Create a working directory:

``` bash
mkdir -p ~/slurm-jobs
cd ~/slurm-jobs
```

Create `cpu-job.sh`:

``` bash
#!/bin/bash
#SBATCH --job-name=cpu-test
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=4G
#SBATCH --time=00:05:00
#SBATCH --output=cpu-%j.out
#SBATCH --error=cpu-%j.err

echo "SLURM CPU JOB"
echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: $(hostname)"
echo "CPUs: ${SLURM_CPUS_PER_TASK}"
date
sleep 30
date
echo "CPU job completed"
```

Submit and monitor:

``` bash
sbatch cpu-job.sh
squeue -u "$USER"
```

Inspect the output:

``` bash
cat cpu-JOBID.out
```

Inspect accounting:

``` bash
sacct -j JOBID \
  --format=JobID,JobName,Partition,State,Elapsed,AllocCPUS,MaxRSS,ExitCode
```

Replace `JOBID` with the job number returned by `sbatch`.

## 16. Interactive execution with `srun` and `salloc`

Run a one-off command through Slurm:

``` bash
srun \
  --partition=cpu \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=4 \
  --mem=8G \
  hostname
```

Request an interactive allocation:

``` bash
salloc \
  --partition=cpu \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=4 \
  --mem=8G
```

Inside the allocation:

``` bash
srun hostname
```

Run the interactive application or debugging commands, then exit the allocation when finished.

- `sbatch`: submit a batch script.
- `srun`: launch a command or job step.
- `salloc`: obtain an allocation, often for interactive work.

## 17. Submit NVIDIA GPU jobs

### 17.1 Verify GPU nodes

On each GPU worker:

``` bash
nvidia-smi
nvidia-smi -L
```

Check Slurm’s view:

``` bash
sudo slurmd -G
```

From the controller:

``` bash
sinfo -N -o "%N %P %G %T"
```

### 17.2 Create a GPU validation job

Create `gpu-test.sh`:

``` bash
#!/bin/bash
#SBATCH --job-name=gpu-test
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=00:15:00
#SBATCH --output=gpu-%j.out
#SBATCH --error=gpu-%j.err

echo "SLURM GPU JOB"
echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: $(hostname)"
echo "CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES}"

nvidia-smi
echo "GPU validation completed"
```

Submit:

``` bash
sbatch gpu-test.sh
squeue -u "$USER"
```

Inspect the job:

``` bash
scontrol show job JOBID
cat gpu-JOBID.out
```

### 17.3 PyTorch GPU workload

Prepare a Python environment on the GPU nodes, or make a compatible environment available through shared storage or a supported container runtime. Ensure the PyTorch CUDA build is compatible with the host NVIDIA driver.

Create `pytorch-gpu.py`:

``` python
import time
import torch

print("PyTorch:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())

if not torch.cuda.is_available():
    raise RuntimeError("CUDA GPU is not available")

device = torch.device("cuda:0")
print("GPU:", torch.cuda.get_device_name(0))

a = torch.randn(4096, 4096, device=device)
b = torch.randn(4096, 4096, device=device)

start = time.time()
for _ in range(100):
    c = torch.matmul(a, b)

torch.cuda.synchronize()

print("Result shape:", tuple(c.shape))
print("Execution time:", time.time() - start)
```

Create `pytorch-gpu-job.sh`:

``` bash
#!/bin/bash
#SBATCH --job-name=pytorch-training
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00
#SBATCH --output=pytorch-%j.out

source /opt/ai-env/bin/activate
python pytorch-gpu.py
```

Submit:

``` bash
sbatch pytorch-gpu-job.sh
```

The environment path `/opt/ai-env` is an example. Create and validate it before submitting the job.

### 17.4 Request multiple GPUs

For a worker with two configured GPUs:

``` bash
sbatch \
  --partition=gpu \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=16 \
  --gres=gpu:2 \
  pytorch-gpu-job.sh
```

A multi-node distributed training job additionally needs a distributed execution strategy, task layout, rendezvous configuration, compatible NCCL/MPI libraries, and high-speed networking. A multi-GPU allocation alone does not automatically distribute a model across nodes.

## 18. Prometheus and Grafana monitoring architecture

Monitor three distinct areas:

1.  Linux infrastructure: CPU, memory, disk, and network.
2.  Slurm: node states, queue, jobs, scheduler, and allocations.
3.  NVIDIA: GPU utilization, memory, temperature, power, and device health.

``` mermaid
flowchart TB
    NE[Node ExporterOS metrics] --> P[PrometheusScraping, time series, alert rules]
    SE[Slurm ExporterQueue and scheduler] --> P
    DE[DCGM ExporterNVIDIA telemetry] --> P
    P --> G[GrafanaHPC and AI dashboards]
```

### 18.1 Monitoring coverage

| Area       | Useful measurements                                       |
|:-----------|:----------------------------------------------------------|
| Cluster    | Total, idle, allocated, down, and drained nodes           |
| Scheduler  | Pending/running jobs, queue length, scheduling statistics |
| CPU        | Utilization, allocated CPUs, idle CPUs                    |
| Memory     | Total, available, allocated, and job memory               |
| GPU        | Utilization, framebuffer memory, temperature, power       |
| Accounting | Job duration, exit code, CPU time, user/account usage     |
| Network    | Throughput, errors, interface state                       |
| Services   | Controller, database, Munge, and exporter availability    |

### 18.2 Install Node Exporter

Install a version-pinned official Prometheus Node Exporter release on all nodes. Create the service account:

``` bash
sudo useradd --system --no-create-home \
  --shell /sbin/nologin node_exporter
```

Install the verified release binary as:

``` text
/usr/local/bin/node_exporter
```

Create `/etc/systemd/system/node_exporter.service`:

``` ini
[Unit]
Description=Prometheus Node Exporter
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
```

Start and verify:

``` bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
curl -s http://localhost:9100/metrics | head
```

Repeat on every node.

### 18.3 Install a Slurm exporter

A community option is `prometheus-slurm-exporter`:

https://github.com/vpenso/prometheus-slurm-exporter

It collects information from Slurm client commands. Review its supported Slurm versions, release notes, metric names, permissions, and build instructions before deployment.

The exporter must be able to run the required Slurm CLI commands and authenticate with Munge. Run it with a dedicated least-privilege service account where possible.

Example endpoint:

``` bash
curl -s http://localhost:9101/metrics | head
```

Do not poll the controller excessively. Start with a 30-second scrape interval and observe controller load.

### 18.4 Install NVIDIA DCGM Exporter

Use NVIDIA’s supported DCGM and DCGM Exporter versions for the installed GPU driver and operating system.

DCGM Exporter commonly exposes Prometheus metrics on TCP port `9400`.

Validate the service and endpoint:

``` bash
systemctl status nvidia-dcgm-exporter
curl -s http://localhost:9400/metrics | head
```

Install and configure the exporter on GPU workers. Follow NVIDIA’s current installation instructions rather than assuming a package name or service unit is identical across releases.

Documentation: https://docs.nvidia.com/datacenter/dcgm/latest/

### 18.5 Prometheus scrape configuration

Create `prometheus.yml`:

``` yaml
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: node-exporter
    static_configs:
      - targets:
          - slurm-master:9100
          - slurm-worker01:9100
          - slurm-worker02:9100
          - slurm-worker03:9100

  - job_name: slurm-exporter
    scrape_interval: 30s
    scrape_timeout: 30s
    static_configs:
      - targets:
          - slurm-master:9101

  - job_name: dcgm-exporter
    static_configs:
      - targets:
          - slurm-worker02:9400
          - slurm-worker03:9400
```

Validate the file with `promtool check config prometheus.yml` using the matching Prometheus release. Deploy Prometheus as a version-pinned service or container with persistent storage and access to the exporter endpoints.

Open:

``` text
http://slurm-master:9090/targets
```

All expected targets should show `UP`.

### 18.6 Grafana deployment

For a lab, Grafana can be deployed with Docker Compose. Pin an approved image version and persist its data.

Example `compose.yaml`:

``` yaml
services:
  grafana:
    image: grafana/grafana:PINNED_VERSION
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
```

Replace `PINNED_VERSION` with a real approved version before running:

``` bash
docker compose up -d
```

Open:

``` text
http://slurm-master:3000
```

Add Prometheus as a Grafana data source:

``` text
http://slurm-master:9090
```

Secure Grafana with authentication, TLS/reverse proxy as appropriate, and restricted network access.

### 18.7 Example PromQL

Metric names depend on exporter versions and configuration. Inspect each endpoint’s `/metrics` output and adapt queries to the actual labels.

| Dashboard panel             | Example PromQL                                                                   |
|:----------------------------|:---------------------------------------------------------------------------------|
| Node CPU utilization        | `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Available memory            | `node_memory_MemAvailable_bytes`                                                 |
| GPU utilization             | `DCGM_FI_DEV_GPU_UTIL`                                                           |
| GPU framebuffer memory used | `DCGM_FI_DEV_FB_USED`                                                            |
| GPU temperature             | `DCGM_FI_DEV_GPU_TEMP`                                                           |

For Slurm job-state metrics, use the exact metric and label names exposed by the installed exporter. Do not assume all exporters expose `slurm_job_state{state="RUNNING"}`.

### 18.8 Recommended Grafana dashboard panels

- Node status: idle, allocated, down, drain.
- CPU utilization by host.
- Allocated and available memory by host.
- Pending, running, completed, and failed jobs.
- Job queue by partition and user.
- GPU allocation by compute node.
- GPU utilization and memory usage.
- GPU temperature and power.
- Network throughput and errors.
- Controller, database, and exporter health.

## 19. End-to-end validation checklist

| Test                 | Command/check                 | Expected outcome            |
|:---------------------|:------------------------------|:----------------------------|
| Host resolution      | `getent hosts slurm-worker01` | Correct IP returned         |
| Time synchronization | `chronyc tracking`            | Clock synchronized          |
| Munge                | `munge -n \| unmunge`         | Success                     |
| Controller           | `systemctl status slurmctld`  | Active                      |
| Worker daemon        | `systemctl status slurmd`     | Active                      |
| Node registration    | `sinfo -N -l`                 | Nodes visible               |
| CPU job              | `sbatch cpu-job.sh`           | Job completes               |
| GPU detection        | `slurmd -G`                   | GPU GRES detected           |
| GPU job              | `sbatch gpu-test.sh`          | GPU allocated               |
| Accounting           | `sacct -j JOBID`              | Historical record available |
| Node exporter        | `curl localhost:9100/metrics` | Metrics returned            |
| Slurm exporter       | `curl localhost:9101/metrics` | Metrics returned            |
| DCGM exporter        | `curl localhost:9400/metrics` | GPU metrics returned        |
| Prometheus           | `/targets`                    | Targets UP                  |
| Grafana              | Dashboard query               | Metrics visualized          |

## 20. Troubleshooting

| Problem                    | Possible cause                                   | First checks                                 |
|:---------------------------|:-------------------------------------------------|:---------------------------------------------|
| Node DOWN                  | `slurmd` unavailable, network or config mismatch | `systemctl status slurmd`; worker logs       |
| Node DRAIN                 | Admin action or node health/configuration issue  | `scontrol show node`                         |
| Munge authentication error | Key, ownership, permissions, time                | `munge -n \| unmunge`; `journalctl -u munge` |
| Job pending                | Resources unavailable or policy constraints      | `squeue -j JOBID -o "%R"`                    |
| GPU missing                | GRES/NVML/device configuration                   | `nvidia-smi`; `slurmd -G`                    |
| GPU job fails              | Driver/runtime/library mismatch                  | `nvidia-smi`; job output                     |
| No accounting records      | SlurmDBD or database issue                       | `systemctl status slurmdbd`; logs            |
| Controller will not start  | Invalid config, missing directory/plugin         | `journalctl -u slurmctld`                    |
| Exporter target DOWN       | Firewall, service, routing, or bind address      | `curl HOST:PORT/metrics`                     |
| Grafana has no data        | Prometheus target/query/data-source issue        | Prometheus `/targets` and query UI           |

Useful administrative commands:

``` bash
# Nodes and partitions
sinfo -N -l
scontrol show node slurm-worker01
scontrol show partition

# Jobs and scheduler
squeue -a
sdiag

# Accounting and reports
sacct
sreport cluster utilization

# Running job statistics
sstat -j JOBID

# Drain a node for maintenance
sudo scontrol update NodeName=slurm-worker01 \
  State=DRAIN Reason="Maintenance"

# Return a node to service after resolving the issue
sudo scontrol update NodeName=slurm-worker01 State=RESUME

# Reconfigure the controller after supported config changes
sudo scontrol reconfigure
```

## 21. Production-readiness recommendations

| Layer                    | Recommended technology   | Purpose                                 |
|:-------------------------|:-------------------------|:----------------------------------------|
| Operating system         | Rocky Linux 9            | Compute operating system                |
| Scheduler                | Slurm                    | Job scheduling and resource allocation  |
| Authentication           | Munge                    | Cluster daemon authentication           |
| Accounting               | SlurmDBD + MariaDB       | Historical job/accounting records       |
| Shared storage           | NFS, BeeGFS, or Lustre   | Home directories, datasets, checkpoints |
| GPU                      | NVIDIA driver and CUDA   | Accelerated compute                     |
| GPU scheduling           | Slurm GRES               | GPU allocation                          |
| GPU telemetry            | DCGM Exporter            | Device metrics                          |
| Infrastructure telemetry | Node Exporter            | OS metrics                              |
| Scheduler telemetry      | Slurm exporter           | Queue and scheduler metrics             |
| Metrics storage          | Prometheus               | Time-series monitoring                  |
| Visualization            | Grafana                  | Dashboards and alerts                   |
| User environments        | Environment Modules      | Python, CUDA, MPI environments          |
| Identity                 | LDAP or Active Directory | Centralized identity                    |

Additional recommendations:

**High availability:** Configure primary and backup Slurm controllers, shared controller state, and a tested failover procedure.

**Shared storage:** Provide appropriate shared storage for home directories, datasets, model checkpoints, and software environments. Not every Slurm workload requires shared storage.

**Fair-share:** Configure accounts, associations, QOS, priorities, and limits so that users share cluster resources according to policy.

**GPU partitioning:** Use GRES for GPU scheduling. Evaluate NVIDIA MIG for supported GPUs and configure Slurm according to the actual device topology.

**Security:** Restrict management ports, protect Munge keys and database credentials, use least-privilege service accounts, enforce cgroup resource limits, and secure monitoring endpoints.

**Backup and recovery:** Back up MariaDB, Slurm configuration, controller state, and user data. Regularly test restore and failover procedures.

## 22. Instructor-led training curriculum

| Lab | Topic                         | Practical outcome                         |
|:----|:------------------------------|:------------------------------------------|
| 01  | HPC and Slurm fundamentals    | Understand the scheduler                  |
| 02  | Rocky Linux 9 preparation     | Prepare controller and workers            |
| 03  | Munge and Slurm configuration | Establish trusted cluster communication   |
| 04  | MariaDB and SlurmDBD          | Enable job accounting                     |
| 05  | CPU job scheduling            | Submit, inspect, and account for CPU jobs |
| 06  | NVIDIA GPU integration        | Submit and validate GPU jobs              |
| 07  | Prometheus and Grafana        | Monitor infrastructure, jobs, and GPUs    |
| 08  | Production administration     | Troubleshooting, QOS, HA, and operations  |

## 23. Final architecture summary

The platform has four logical layers:

1.  **Access layer:** Login node, SSH, Slurm CLI, user environments.
2.  **Management layer:** `slurmctld`, `slurmdbd`, MariaDB, scheduling, accounting.
3.  **Compute layer:** Rocky Linux workers, CPU, RAM, NVIDIA GPU, CUDA, PyTorch, MPI.
4.  **Monitoring layer:** Node Exporter, Slurm Exporter, DCGM Exporter, Prometheus, Grafana.

**Recommended implementation approach**

> Automate this environment with Ansible roles for common OS preparation, Munge, controller, compute nodes, GPU configuration, accounting, and monitoring. Pin software versions and keep secrets in Ansible Vault or another secrets manager. Validate each layer before moving to the next.

## 24. Official documentation and project references

- Slurm documentation: https://slurm.schedmd.com/documentation.html
- Slurm administrator quick start: https://slurm.schedmd.com/quickstart_admin.html
- Slurm GRES and GPU scheduling: https://slurm.schedmd.com/gres.html
- Slurm cgroup configuration: https://slurm.schedmd.com/cgroup.conf.html
- Slurm accounting: https://slurm.schedmd.com/accounting.html
- OpenHPC: https://openhpc.community/
- Prometheus: https://prometheus.io/docs/
- Node Exporter: https://github.com/prometheus/node_exporter
- Prometheus Slurm Exporter: https://github.com/vpenso/prometheus-slurm-exporter
- NVIDIA DCGM: https://docs.nvidia.com/datacenter/dcgm/latest/
- NVIDIA DCGM Exporter: https://github.com/NVIDIA/dcgm-exporter

------------------------------------------------------------------------

**End of guide — Slurm on Rocky Linux 9 for AI and HPC workloads.**
