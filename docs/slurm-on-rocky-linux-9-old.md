 
# Slurm Workload Manager on Rocky Linux 9: Complete Hands-on HPC Lab

## 1. Introduction

Slurm (Simple Linux Utility for Resource Management) is an open-source workload manager and job scheduler widely used in High Performance Computing (HPC) environments.

It manages compute resources, schedules workloads, allocates CPUs and memory, executes jobs across compute nodes, and tracks job utilization.

In this hands-on lab, we build a two-node Slurm cluster using Rocky Linux 9 and explore practical job scheduling, resource management, accounting, priorities, dependencies, and job arrays.

### What we will learn

1. Slurm architecture and components
2. Slurm installation and configuration overview
3. MUNGE authentication
4. Slurm controller and compute node
5. Partitions and resource management
6. Interactive jobs using `srun`
7. Batch jobs using `sbatch`
8. Job monitoring using `squeue`
9. CPU and memory allocation
10. Job priorities using `sprio`
11. Accounting using SlurmDBD and MariaDB
12. Job dependencies
13. Job arrays
14. Troubleshooting and validation

---

## 2. Lab architecture

### Cluster topology

| Component | Hostname | IP address | Role |
|---|---|---|---|
| Controller | master | 192.168.232.20 | Slurm controller and accounting |
| Compute node | node01 | 192.168.232.21 | Executes HPC workloads |

### Environment

| Component | Version / configuration |
|---|---|
| Operating system | Rocky Linux 9.8 |
| Slurm | 22.05.11 |
| MUNGE | Authentication service |
| Database | MariaDB 10.5.29 |
| SlurmDBD | Accounting daemon |
| Partition | compute |
| Compute CPUs | 4 |
| Compute memory | Approximately 15.6 GiB |
| Cluster name | hpc-lab |

### Architecture diagram

```text
                   HPC USER
                      |
                      |
                 Submit Jobs
                      |
             sbatch / srun / squeue
                      |
                      v
       +-----------------------------+
       |         MASTER              |
       |       192.168.232.20        |
       |                             |
       |       slurmctld             |
       |       slurmdbd              |
       |       MariaDB               |
       |       MUNGE                 |
       +-----------------------------+
                      |
             Slurm scheduling
                      |
             MUNGE authentication
                      |
                      v
       +-----------------------------+
       |         NODE01              |
       |       192.168.232.21        |
       |                             |
       |       slurmd                |
       |       MUNGE                 |
       |                             |
       |       4 CPUs                |
       |       15.6 GiB RAM          |
       +-----------------------------+
                      |
                      v
                HPC WORKLOADS
```

---

## 3. Slurm architecture and components

Slurm consists of several important components.

| Component | Description | Location |
|---|---|---|
| `slurmctld` | Central scheduler and resource manager | Controller |
| `slurmd` | Executes jobs and manages node resources | Compute node |
| `slurmdbd` | Collects and provides accounting information | Controller |
| MUNGE | Authenticates users and Slurm services | All nodes |
| MariaDB | Stores Slurm accounting information | Controller |
| `sbatch` | Submits batch jobs | Client |
| `srun` | Runs interactive or job-step workloads | Client |
| `squeue` | Displays queued and running jobs | Client |
| `sacct` | Displays job accounting information | Client |
| `sinfo` | Displays node and partition information | Client |

### Job execution workflow

1. A user submits a job using `sbatch` or `srun`.
2. `slurmctld` receives the request.
3. The scheduler checks available resources and job priority.
4. The scheduler selects an eligible compute node.
5. `slurmd` launches the workload.
6. The workload executes on the allocated compute node.
7. Job state and accounting information are recorded through SlurmDBD.

---

## 4. MUNGE authentication

MUNGE provides authentication between Slurm components.

It allows services on different cluster nodes to verify credentials securely.

Check MUNGE:

```bash
systemctl status munge
```

Test credential generation:

```bash
munge -n | unmunge
```

Test authentication across nodes:

```bash
munge -n | ssh node01 unmunge
```

The cross-node test should successfully decode the credential.

Important: MUNGE must use a consistent shared key across all cluster nodes. Protect the key and restrict its permissions.

---

## 5. Slurm configuration

The primary configuration file is:

```bash
/etc/slurm/slurm.conf
```

Important configuration parameters:

```ini
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

Note: This is a representative configuration from the lab. Paths, users, node resources, and authentication settings must match the actual installation.

Validate the running configuration:

```bash
scontrol show config
scontrol show node node01
scontrol show partition compute
scontrol ping
```

---

## 6. Understanding Slurm partitions

A partition is a logical grouping of compute nodes and scheduling policies.

Our cluster contains one partition:

```ini
PartitionName=compute Nodes=node01 Default=YES State=UP
```

View partitions:

```bash
sinfo
```

Detailed partition information:

```bash
scontrol show partition compute
```

A partition can define limits such as:

- Maximum execution time
- Maximum nodes per job
- Maximum CPUs per node
- Allowed compute nodes
- Default scheduling behavior

Example: requesting two hours when the partition allows only one hour results in the job being ineligible due to its time limit.

---

## 7. Interactive jobs using srun

` srun ` is used to execute interactive commands or job steps through Slurm.

Example:

```bash
srun -p compute -N 1 -n 1 hostname
```

Expected:

```text
node01
```

Run four tasks:

```bash
srun -p compute -N 1 -n 4 \
  bash -c 'echo "Task $SLURM_PROCID running on $(hostname)"'
```

This demonstrates how Slurm allocates tasks to a compute node.

---

## 8. Batch jobs using sbatch

Batch jobs are submitted as scripts and executed when resources become available.

Create a script:

```bash
vi hello-hpc.sh
```

Script:

```bash
#!/bin/bash

#SBATCH --job-name=hello-hpc
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:02:00
#SBATCH --output=hello-%j.out

echo "Hello HPC!"
echo "Job ID: $SLURM_JOB_ID"
echo "Running on: $(hostname)"
echo "Started: $(date)"

sleep 10

echo "Job completed: $(date)"
```

Submit:

```bash
sbatch hello-hpc.sh
```

Check status:

```bash
squeue
```

View output:

```bash
cat hello-JOBID.out
```

Replace `JOBID` with the actual job ID.

---

## 9. Job monitoring

Important Slurm monitoring commands:

| Command | Purpose |
|---|---|
| `squeue` | Show queued and running jobs |
| `sinfo` | Show nodes and partitions |
| `scontrol show job JOBID` | Detailed job information |
| `scontrol show node node01` | Detailed node information |
| `scancel JOBID` | Cancel a job |
| `sacct` | Show historical job accounting |
| `sprio` | Display job priority components |
| `sreport` | Generate cluster utilization reports |

Examples:

```bash
squeue -u hpcuser

sinfo -N -l

scontrol show job 30

scancel 30
```

---

## 10. CPU and memory resource allocation

Slurm can allocate CPU and memory resources to individual jobs.

Example:

```bash
sbatch \
  --partition=compute \
  --ntasks=1 \
  --cpus-per-task=2 \
  --mem=2G \
  --time=00:02:00 \
  resource-test.sh
```

A resource allocation test script:

```bash
#!/bin/bash

echo "Job ID: $SLURM_JOB_ID"
echo "Allocated CPUs: $SLURM_CPUS_PER_TASK"
echo "Memory requested: 2 GB"
echo "Node: $(hostname)"

sleep 30
```

Inspect resource allocation:

```bash
scontrol show job JOBID
```

Useful fields include:

- `NumCPUs`
- `ReqTRES`
- `AllocTRES`
- `ReqMem`
- `AllocCPUS`

Example from the lab:

```text
AllocCPUS=1
AllocMem=2048
AllocTRES=cpu=1,mem=2G
```

This demonstrates that Slurm allocated one CPU and 2 GiB of memory to the job.

Note: Requested memory and actual memory consumption are different measurements.

---

## 11. Job priorities using multifactor scheduling

Slurm supports job prioritization.

Our lab uses:

```ini
PriorityType=priority/multifactor

PriorityWeightAge=1000
PriorityWeightFairShare=10000
PriorityWeightJobSize=1000
PriorityWeightPartition=1000
PriorityWeightQOS=1000
```

The multifactor plugin calculates priority using configured factors.

Inspect priorities:

```bash
sprio -u hpcuser
```

Submit a normal-priority job:

```bash
sbatch --nice=0 normal-job.sh
```

Submit a lower-priority job:

```bash
sbatch --nice=1000 lower-priority-job.sh
```

In our experiment, the two pending jobs differed by 1000 priority points.

This demonstrated how the `--nice` value influences job priority.

Other useful concepts:

- Age
- FairShare
- Job size
- Partition
- Quality of Service (QOS)
- TRES-based priority

---

## 12. Slurm accounting using SlurmDBD and MariaDB

SlurmDBD provides accounting services for Slurm.

MariaDB stores accounting information.

Architecture:

```text
Slurm jobs
    |
    v
slurmctld
    |
    v
slurmdbd
    |
    v
MariaDB
    |
    v
slurm_acct_db
```

Important configuration:

```ini
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=master
AccountingStoragePort=6819
```

SlurmDBD configuration file:

```bash
/etc/slurm/slurmdbd.conf
```

Important: This file contains database credentials. Keep it restricted to the Slurm service account and never commit it to GitHub.

Check service:

```bash
systemctl status slurmdbd
```

Check cluster registration:

```bash
sacctmgr show cluster
```

View accounts and associations:

```bash
sacctmgr show account
sacctmgr show associations
```

View job accounting:

```bash
sacct -j JOBID \
  --format=JobID,JobName,User,Account,State,ExitCode,Elapsed
```

Generate utilization reports:

```bash
sreport cluster utilization \
  start=2026-11-06 end=2026-11-07
```

---

## 13. Job dependencies

Job dependencies allow one job to wait for another job to finish.

Example workflow:

```text
Job A: Data preparation
          |
          | afterok
          v
Job B: Data processing
          |
          | afterok
          v
Job C: Report generation
```

Submit Job A:

```bash
JOB_A=$(sbatch --parsable 01-data-preparation.sh)
```

Submit Job B:

```bash
JOB_B=$(sbatch --parsable \
  --dependency=afterok:$JOB_A \
  02-data-processing.sh)
```

Submit Job C:

```bash
JOB_C=$(sbatch --parsable \
  --dependency=afterok:$JOB_B \
  03-report-generation.sh)
```

Monitor:

```bash
squeue
```

Review:

```bash
sacct -j "$JOB_A","$JOB_B","$JOB_C" \
  --format=JobID,JobName,State,ExitCode,Elapsed
```

Dependency types:

| Dependency | Meaning |
|---|---|
| `after` | Wait until the specified job has started |
| `afterok` | Wait until the specified job completes successfully |
| `afterany` | Wait until the specified job terminates |
| `afternotok` | Wait until the specified job terminates unsuccessfully |
| `singleton` | Wait for earlier jobs with the same name and user |

### Actual lab result

We successfully executed:

| Job | Stage | Result |
|---|---|---|
| 30 | Data preparation | COMPLETED |
| 31 | Data processing | COMPLETED |
| 32 | Report generation | COMPLETED |

The final report contained:

```text
HPC Processing Report

Count=5
Sum=515
Average=103.00
```

All three jobs completed with exit code `0:0`.

---

## 14. Slurm job arrays

Job arrays allow users to submit multiple similar tasks through one submission.

Example:

```bash
sbatch --array=1-5 process-dataset.sh
```

Limit concurrent tasks:

```bash
sbatch --array=1-5%2 process-dataset.sh
```

Here:

- `1-5` creates five tasks.
- `%2` allows a maximum of two concurrent tasks.

Each task receives its own array index.

Example script:

```bash
#!/bin/bash

TASK_ID=$SLURM_ARRAY_TASK_ID

BASE=$((TASK_ID * 100))

echo "Array Job: $SLURM_ARRAY_JOB_ID"
echo "Task ID: $TASK_ID"
echo "Node: $(hostname)"

for i in {1..5}; do
    echo $((BASE + i))
done
```

Important environment variables:

| Variable | Description |
|---|---|
| `SLURM_ARRAY_JOB_ID` | Parent array job ID |
| `SLURM_ARRAY_TASK_ID` | Individual task index |
| `SLURM_ARRAY_TASK_COUNT` | Total number of array tasks |
| `SLURM_JOB_ID` | Job identifier |

Monitor array tasks:

```bash
squeue -u hpcuser
```

View accounting:

```bash
sacct -j ARRAY_JOB_ID \
  --format=JobID,JobName,State,ExitCode,Elapsed,NodeList
```

### Actual lab result

We submitted five tasks:

```bash
sbatch --array=1-5%2 process-dataset.sh
```

Slurm assigned array job ID `33`.

All five tasks completed successfully:

| Task | Job ID | State |
|---|---|---|
| 1 | 33_1 | COMPLETED |
| 2 | 33_2 | COMPLETED |
| 3 | 33_3 | COMPLETED |
| 4 | 33_4 | COMPLETED |
| 5 | 33_5 | COMPLETED |

Each task executed on `node01`.

This is useful for parameter sweeps, independent simulations, batch preprocessing, and ML experiments.

---

## 15. Important operational considerations

### User consistency

Linux user accounts should have consistent UID and GID values across cluster nodes.

Example:

```bash
id hpcuser
```

### SSH connectivity

For administrative and operational workflows:

```bash
ssh node01 hostname
```

SSH keys can simplify trusted administrative connectivity. Use appropriate access controls rather than enabling unrestricted root access.

### Filesystem considerations

Our lab uses local filesystems, not shared storage.

Therefore:

- Job scripts are submitted from `master`.
- Jobs execute on `node01`.
- Runtime output files are created on `node01`.
- Data required by jobs must be available on the compute node.

For production HPC environments, shared storage is commonly used.

### Configuration consistency

Keep `/etc/slurm/slurm.conf` consistent across nodes.

Check:

```bash
sha256sum /etc/slurm/slurm.conf
```

### Service validation

Controller:

```bash
systemctl status slurmctld
systemctl status slurmdbd
```

Compute node:

```bash
systemctl status slurmd
```

---

## 16. Slurm command cheat sheet

| Task | Command |
|---|---|
| Check cluster | `sinfo` |
| Check nodes | `sinfo -N -l` |
| Submit batch job | `sbatch job.sh` |
| Run interactive job | `srun hostname` |
| View jobs | `squeue` |
| View user jobs | `squeue -u hpcuser` |
| Cancel job | `scancel JOBID` |
| Inspect job | `scontrol show job JOBID` |
| Inspect node | `scontrol show node node01` |
| View accounting | `sacct -j JOBID` |
| View priority | `sprio` |
| View accounts | `sacctmgr show account` |
| View utilization | `sreport cluster utilization` |
| Submit job array | `sbatch --array=1-10 job.sh` |
| Submit dependent job | `sbatch --dependency=afterok:JOBID job.sh` |

---

## 17. Practical learning outcomes

Through this lab, we successfully demonstrated:

- Two-node Slurm cluster operation.
- MUNGE authentication between nodes.
- Controller and compute-node services.
- Partition configuration and scheduling.
- Interactive and batch job execution.
- CPU and memory resource allocation.
- Multifactor job prioritization.
- SlurmDBD and MariaDB accounting.
- Job dependencies and sequential workflows.
- Job arrays with concurrent task limits.
- Job monitoring and accounting validation.

The lab used a CPU-only compute node. GPU scheduling, GPU resource configuration, and NVIDIA workload execution are not yet validated in this environment.

---

## 18. Conclusion

Slurm is an important platform for managing HPC workloads, from traditional scientific computing to AI and machine learning workloads.

Understanding job scheduling, resource allocation, accounting, dependencies, and arrays provides a strong foundation for building and operating HPC clusters.

This hands-on project demonstrates the core Slurm workload-management concepts using Rocky Linux 9.

**Next learning topics:**

1. GPU scheduling with Slurm and NVIDIA GPUs.
2. Slurm GRES configuration.
3. Multi-node MPI workloads.
4. Prometheus and Grafana monitoring.
5. Slurm and Kubernetes integration.
6. Production HPC cluster deployment using Ansible.

---

## Lab environment

- OS: Rocky Linux 9.8
- Slurm: 22.05.11
- Cluster: hpc-lab
- Controller: master
- Compute node: node01
- Partition: compute

*This article documents a practical learning lab. Production deployments require additional security, high availability, shared storage, capacity planning, and operational validation.*

