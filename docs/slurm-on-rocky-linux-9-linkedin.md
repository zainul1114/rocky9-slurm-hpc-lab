🚀 **Hands-on HPC Learning: Building a Slurm Cluster on Rocky Linux 9**

I have been exploring High Performance Computing (HPC) and recently completed a hands-on Slurm Workload Manager lab using Rocky Linux 9.

Rather than focusing only on theory, I built a two-node cluster and practiced how Slurm manages compute resources and schedules workloads.

**Lab architecture:**
- Controller: master — 192.168.232.20
- Compute node: node01 — 192.168.232.21
- OS: Rocky Linux 9.8
- Slurm: 22.05.11
- Accounting: SlurmDBD + MariaDB

**What I implemented and learned:**

✅ Slurm architecture and core components  
✅ MUNGE authentication  
✅ Controller and compute-node configuration  
✅ Partitions and resource management  
✅ Interactive jobs using `srun`  
✅ Batch jobs using `sbatch`  
✅ CPU and memory allocation  
✅ Job monitoring using `squeue` and `sinfo`  
✅ Multifactor job priorities using `sprio`  
✅ Job accounting using `SlurmDBD`, `MariaDB`, `sacct`, and `sreport`  
✅ Job dependencies using `afterok`  
✅ Job arrays using `--array`

**A few practical results:**

- Successfully executed interactive and batch workloads.
- Validated CPU and memory allocation.
- Built a three-stage data-processing pipeline using job dependencies.
- Executed five independent array tasks with a maximum of two concurrent tasks.
- Verified job completion and accounting through SlurmDBD.

This hands-on exercise helped me understand how HPC workloads are submitted, scheduled, executed, monitored, and accounted for.

**Next on my learning roadmap:**
- NVIDIA GPU scheduling with Slurm
- GRES configuration
- MPI workloads
- Prometheus and Grafana monitoring
- HPC and Kubernetes integration

I have documented the architecture, configuration examples, commands, and practical exercises in the GitHub project.

📘 GitHub: [Add your repository URL here]

Feedback and suggestions from the HPC and DevOps community are welcome!

#HPC #Slurm #RockyLinux #Linux #HighPerformanceComputing #DevOps #LinuxAdministration #AIInfrastructure #MLOps #NVIDIA
