use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use clap::{Parser, Subcommand};
use colored::*;
use dialoguer::{Confirm, Input, Select};
use indicatif::{ProgressBar, ProgressStyle};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tabled::{Table, Tabled};

#[derive(Parser)]
#[command(name = "fc-vps")]
#[command(version = "0.1.0")]
#[command(about = "Firecracker VPS Management CLI")]
#[command(long_about = None)]
struct Cli {
    #[arg(short, long, default_value = "http://localhost:8080")]
    #[arg(env = "FC_VPS_SERVER")]
    server: String,

    #[arg(short, long)]
    #[arg(help = "Enable verbose output")]
    verbose: bool,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create a new VPS instance
    Create {
        /// Name of the VPS
        #[arg(short, long)]
        name: Option<String>,

        /// Number of CPU cores (1-8)
        #[arg(short, long, default_value = "1")]
        cpu: u32,

        /// Memory in MB (128-8192)
        #[arg(short, long, default_value = "512")]
        memory: u32,

        /// Disk size in GB (1-100)
        #[arg(short, long, default_value = "10")]
        disk: u32,

        /// Base image to use
        #[arg(short, long)]
        image: Option<String>,

        /// Interactive mode
        #[arg(short = 'i', long)]
        interactive: bool,
    },
    /// List all VPS instances
    List {
        /// Show detailed information
        #[arg(short, long)]
        detailed: bool,

        /// Filter by status
        #[arg(short, long)]
        status: Option<String>,
    },
    /// Show VPS details
    Get {
        /// VPS ID or name
        id: String,

        /// Show in JSON format
        #[arg(short, long)]
        json: bool,
    },
    /// Start a VPS
    Start {
        /// VPS ID or name
        id: String,

        /// Wait for VPS to be ready
        #[arg(short, long)]
        wait: bool,
    },
    /// Stop a VPS
    Stop {
        /// VPS ID or name
        id: String,

        /// Force stop without confirmation
        #[arg(short, long)]
        force: bool,
    },
    /// Delete a VPS
    Delete {
        /// VPS ID or name
        id: String,

        /// Force delete without confirmation
        #[arg(short, long)]
        force: bool,
    },
    /// Show service health
    Health,
    /// Interactive management console
    Console,
}

#[derive(Serialize, Deserialize, Debug)]
struct VM {
    id: String,
    name: String,
    cpu: u32,
    memory: u32,
    disk_size: u32,
    image: String,
    status: String,
    ip_address: String,
    created_at: DateTime<Utc>,
    socket_path: String,
    kernel_path: String,
    rootfs_path: String,
    tap_device: String,
}

#[derive(Tabled)]
struct VMTableRow {
    #[tabled(rename = "ID")]
    id: String,
    #[tabled(rename = "Name")]
    name: String,
    #[tabled(rename = "Status")]
    status: String,
    #[tabled(rename = "CPU")]
    cpu: String,
    #[tabled(rename = "Memory")]
    memory: String,
    #[tabled(rename = "Disk")]
    disk: String,
    #[tabled(rename = "IP Address")]
    ip_address: String,
    #[tabled(rename = "Created")]
    created: String,
}

#[derive(Serialize)]
struct VMRequest {
    name: String,
    cpu: u32,
    memory: u32,
    disk_size: u32,
    image: String,
}

#[derive(Deserialize)]
struct ApiResponse<T> {
    success: bool,
    message: String,
    data: Option<T>,
}

struct VPSClient {
    client: Client,
    base_url: String,
    verbose: bool,
}

impl VPSClient {
    fn new(base_url: String, verbose: bool) -> Self {
        Self {
            client: Client::new(),
            base_url,
            verbose,
        }
    }

    async fn create_vm(&self, request: VMRequest) -> Result<VM> {
        if self.verbose {
            println!(
                "Creating VPS with request: {}",
                serde_json::to_string_pretty(&request)?
            );
        }

        let response = self
            .client
            .post(&format!("{}/api/v1/vms", self.base_url))
            .json(&request)
            .send()
            .await
            .context("Failed to send create VM request")?;

        let api_response: ApiResponse<VM> = response
            .json()
            .await
            .context("Failed to parse create VM response")?;

        if !api_response.success {
            anyhow::bail!("API Error: {}", api_response.message);
        }

        api_response.data.context("No VM data in response")
    }

    async fn list_vms(&self) -> Result<Vec<VM>> {
        if self.verbose {
            println!("Fetching VPS list...");
        }

        let response = self
            .client
            .get(&format!("{}/api/v1/vms", self.base_url))
            .send()
            .await
            .context("Failed to send list VMs request")?;

        let api_response: ApiResponse<Vec<VM>> = response
            .json()
            .await
            .context("Failed to parse list VMs response")?;

        if !api_response.success {
            anyhow::bail!("API Error: {}", api_response.message);
        }

        Ok(api_response.data.unwrap_or_default())
    }

    async fn get_vm(&self, id: &str) -> Result<VM> {
        if self.verbose {
            println!("Fetching VPS details for: {}", id);
        }

        let response = self
            .client
            .get(&format!("{}/api/v1/vms/{}", self.base_url, id))
            .send()
            .await
            .context("Failed to send get VM request")?;

        let api_response: ApiResponse<VM> = response
            .json()
            .await
            .context("Failed to parse get VM response")?;

        if !api_response.success {
            anyhow::bail!("API Error: {}", api_response.message);
        }

        api_response.data.context("No VM data in response")
    }

    async fn start_vm(&self, id: &str) -> Result<()> {
        if self.verbose {
            println!("Starting VPS: {}", id);
        }

        let response = self
            .client
            .post(&format!("{}/api/v1/vms/{}/start", self.base_url, id))
            .send()
            .await
            .context("Failed to send start VM request")?;

        let api_response: ApiResponse<()> = response
            .json()
            .await
            .context("Failed to parse start VM response")?;

        if !api_response.success {
            anyhow::bail!("API Error: {}", api_response.message);
        }

        Ok(())
    }

    async fn stop_vm(&self, id: &str) -> Result<()> {
        if self.verbose {
            println!("Stopping VPS: {}", id);
        }

        let response = self
            .client
            .post(&format!("{}/api/v1/vms/{}/stop", self.base_url, id))
            .send()
            .await
            .context("Failed to send stop VM request")?;

        let api_response: ApiResponse<()> = response
            .json()
            .await
            .context("Failed to parse stop VM response")?;

        if !api_response.success {
            anyhow::bail!("API Error: {}", api_response.message);
        }

        Ok(())
    }

    async fn delete_vm(&self, id: &str) -> Result<()> {
        if self.verbose {
            println!("Deleting VPS: {}", id);
        }

        let response = self
            .client
            .delete(&format!("{}/api/v1/vms/{}", self.base_url, id))
            .send()
            .await
            .context("Failed to send delete VM request")?;

        let api_response: ApiResponse<()> = response
            .json()
            .await
            .context("Failed to parse delete VM response")?;

        if !api_response.success {
            anyhow::bail!("API Error: {}", api_response.message);
        }

        Ok(())
    }

    async fn health_check(&self) -> Result<bool> {
        if self.verbose {
            println!("Checking service health...");
        }

        let response = self
            .client
            .get(&format!("{}/health", self.base_url))
            .timeout(Duration::from_secs(5))
            .send()
            .await
            .context("Failed to connect to service")?;

        Ok(response.status().is_success())
    }

    async fn find_vm_by_name_or_id(&self, name_or_id: &str) -> Result<VM> {
        // First try to get by ID
        if let Ok(vm) = self.get_vm(name_or_id).await {
            return Ok(vm);
        }

        // If that fails, search by name
        let vms = self.list_vms().await?;
        for vm in vms {
            if vm.name == name_or_id {
                return Ok(vm);
            }
        }

        anyhow::bail!("VPS with name or ID '{}' not found", name_or_id)
    }
}

impl From<VM> for VMTableRow {
    fn from(vm: VM) -> Self {
        Self {
            id: vm.id[..8].to_string(), // Show short ID
            name: vm.name,
            status: match vm.status.as_str() {
                "running" => vm.status.green().to_string(),
                "stopped" => vm.status.red().to_string(),
                "created" => vm.status.yellow().to_string(),
                _ => vm.status,
            },
            cpu: format!("{}c", vm.cpu),
            memory: format!("{}MB", vm.memory),
            disk: format!("{}GB", vm.disk_size),
            ip_address: vm.ip_address,
            created: vm.created_at.format("%Y-%m-%d %H:%M").to_string(),
        }
    }
}

async fn handle_create(
    client: &VPSClient,
    name: Option<String>,
    cpu: u32,
    memory: u32,
    disk: u32,
    image: Option<String>,
    interactive: bool,
) -> Result<()> {
    let request = if interactive {
        println!("{}", "🚀 Creating a new VPS".bold().cyan());
        println!();

        let name = Input::<String>::new()
            .with_prompt("VPS Name")
            .default(format!("vps-{}", chrono::Utc::now().timestamp()))
            .interact_text()?;

        let images = vec!["ubuntu-20.04", "ubuntu-22.04", "ubuntu-24.04", "centos-7", "debian-11"];
        let image_idx = Select::new()
            .with_prompt("Select base image")
            .items(&images)
            .default(0)
            .interact()?;

        let cpu = Input::<u32>::new()
            .with_prompt("CPU cores (1-8)")
            .default(1)
            .validate_with(|input: &u32| -> Result<(), &str> {
                if *input >= 1 && *input <= 8 {
                    Ok(())
                } else {
                    Err("CPU cores must be between 1 and 8")
                }
            })
            .interact_text()?;

        let memory = Input::<u32>::new()
            .with_prompt("Memory in MB (128-8192)")
            .default(512)
            .validate_with(|input: &u32| -> Result<(), &str> {
                if *input >= 128 && *input <= 8192 {
                    Ok(())
                } else {
                    Err("Memory must be between 128MB and 8192MB")
                }
            })
            .interact_text()?;

        let disk_size = Input::<u32>::new()
            .with_prompt("Disk size in GB (1-100)")
            .default(10)
            .validate_with(|input: &u32| -> Result<(), &str> {
                if *input >= 1 && *input <= 100 {
                    Ok(())
                } else {
                    Err("Disk size must be between 1GB and 100GB")
                }
            })
            .interact_text()?;

        VMRequest {
            name,
            cpu,
            memory,
            disk_size: disk_size,
            image: images[image_idx].to_string(),
        }
    } else {
        let name = name.unwrap_or_else(|| format!("vps-{}", chrono::Utc::now().timestamp()));
        let image = image.unwrap_or_else(|| "ubuntu-24.04".to_string());

        // Validate inputs
        if !(1..=8).contains(&cpu) {
            anyhow::bail!("CPU cores must be between 1 and 8");
        }
        if !(128..=8192).contains(&memory) {
            anyhow::bail!("Memory must be between 128MB and 8192MB");
        }
        if !(1..=100).contains(&disk) {
            anyhow::bail!("Disk size must be between 1GB and 100GB");
        }

        VMRequest {
            name,
            cpu,
            memory,
            disk_size: disk,
            image,
        }
    };

    println!("Creating VPS '{}'...", request.name);

    let pb = ProgressBar::new_spinner();
    pb.set_style(
        ProgressStyle::default_spinner()
            .template("{spinner:.green} {msg}")
            .unwrap(),
    );
    pb.set_message("Creating VM...");
    pb.enable_steady_tick(Duration::from_millis(100));

    let vm = client.create_vm(request).await?;
    pb.finish_with_message("✅ VPS created successfully!");

    println!();
    println!("{}", "VPS Details:".bold());
    println!("  ID: {}", vm.id);
    println!("  Name: {}", vm.name.bold());
    println!("  CPU: {} cores", vm.cpu);
    println!("  Memory: {}MB", vm.memory);
    println!("  Disk: {}GB", vm.disk_size);
    println!("  IP Address: {}", vm.ip_address.cyan());
    println!("  Status: {}", vm.status.yellow());
    println!();
    println!(
        "💡 Use '{}' to start your VPS",
        format!("fc-vps start {}", vm.id).cyan()
    );

    Ok(())
}

async fn handle_list(
    client: &VPSClient,
    detailed: bool,
    status_filter: Option<String>,
) -> Result<()> {
    let vms = client.list_vms().await?;

    if vms.is_empty() {
        println!("{}", "No VPS instances found".yellow());
        println!(
            "💡 Create your first VPS with: {}",
            "fc-vps create --interactive".cyan()
        );
        return Ok(());
    }

    let filtered_vms: Vec<VM> = if let Some(status) = status_filter {
        vms.into_iter()
            .filter(|vm| vm.status.eq_ignore_ascii_case(&status))
            .collect()
    } else {
        vms
    };

    if filtered_vms.is_empty() {
        println!("{}", "No VPS instances match the filter criteria".yellow());
        return Ok(());
    }

    if detailed {
        for vm in filtered_vms {
            println!("─────────────────────────────────────");
            println!("{}: {}", "ID".bold(), vm.id);
            println!("{}: {}", "Name".bold(), vm.name);
            println!("{}: {}", "Status".bold(), format_status(&vm.status));
            println!("{}: {} cores", "CPU".bold(), vm.cpu);
            println!("{}: {}MB", "Memory".bold(), vm.memory);
            println!("{}: {}GB", "Disk".bold(), vm.disk_size);
            println!("{}: {}", "Image".bold(), vm.image);
            println!("{}: {}", "IP Address".bold(), vm.ip_address.cyan());
            println!(
                "{}: {}",
                "Created".bold(),
                vm.created_at.format("%Y-%m-%d %H:%M:%S UTC")
            );
            println!();
        }
    } else {
        let table_rows: Vec<VMTableRow> = filtered_vms.into_iter().map(|vm| vm.into()).collect();
        let table = Table::new(table_rows);
        println!("{}", table);
    }

    Ok(())
}

async fn handle_get(client: &VPSClient, id: &str, json: bool) -> Result<()> {
    let vm = client.find_vm_by_name_or_id(id).await?;

    if json {
        println!("{}", serde_json::to_string_pretty(&vm)?);
    } else {
        println!("{}", "VPS Details".bold().cyan());
        println!("─────────────────────────────────────");
        println!("{}: {}", "ID".bold(), vm.id);
        println!("{}: {}", "Name".bold(), vm.name);
        println!("{}: {}", "Status".bold(), format_status(&vm.status));
        println!("{}: {} cores", "CPU".bold(), vm.cpu);
        println!("{}: {}MB", "Memory".bold(), vm.memory);
        println!("{}: {}GB", "Disk".bold(), vm.disk_size);
        println!("{}: {}", "Image".bold(), vm.image);
        println!("{}: {}", "IP Address".bold(), vm.ip_address.cyan());
        println!("{}: {}", "Socket Path".bold(), vm.socket_path);
        println!("{}: {}", "Kernel Path".bold(), vm.kernel_path);
        println!("{}: {}", "Root FS Path".bold(), vm.rootfs_path);
        println!("{}: {}", "TAP Device".bold(), vm.tap_device);
        println!(
            "{}: {}",
            "Created".bold(),
            vm.created_at.format("%Y-%m-%d %H:%M:%S UTC")
        );
    }

    Ok(())
}

async fn handle_start(client: &VPSClient, id: &str, wait: bool) -> Result<()> {
    let vm = client.find_vm_by_name_or_id(id).await?;

    if vm.status == "running" {
        println!(
            "{}",
            format!("VPS '{}' is already running", vm.name).yellow()
        );
        return Ok(());
    }

    println!("Starting VPS '{}'...", vm.name);

    let pb = ProgressBar::new_spinner();
    pb.set_style(
        ProgressStyle::default_spinner()
            .template("{spinner:.green} {msg}")
            .unwrap(),
    );
    pb.set_message("Starting VM...");
    pb.enable_steady_tick(Duration::from_millis(100));

    client.start_vm(&vm.id).await?;

    if wait {
        pb.set_message("Waiting for VM to be ready...");
        // Add logic to wait for VM to be fully started
        tokio::time::sleep(Duration::from_secs(3)).await;
    }

    pb.finish_with_message("✅ VPS started successfully!");

    println!();
    println!("🎉 VPS '{}' is now running!", vm.name.bold());
    println!("   IP Address: {}", vm.ip_address.cyan());
    println!("   SSH: {}", format!("ssh user@{}", vm.ip_address).cyan());

    Ok(())
}

async fn handle_stop(client: &VPSClient, id: &str, force: bool) -> Result<()> {
    let vm = client.find_vm_by_name_or_id(id).await?;

    if vm.status == "stopped" {
        println!(
            "{}",
            format!("VPS '{}' is already stopped", vm.name).yellow()
        );
        return Ok(());
    }

    if !force {
        let confirm = Confirm::new()
            .with_prompt(&format!("Are you sure you want to stop VPS '{}'?", vm.name))
            .default(false)
            .interact()?;

        if !confirm {
            println!("Operation cancelled");
            return Ok(());
        }
    }

    println!("Stopping VPS '{}'...", vm.name);

    let pb = ProgressBar::new_spinner();
    pb.set_style(
        ProgressStyle::default_spinner()
            .template("{spinner:.red} {msg}")
            .unwrap(),
    );
    pb.set_message("Stopping VM...");
    pb.enable_steady_tick(Duration::from_millis(100));

    client.stop_vm(&vm.id).await?;
    pb.finish_with_message("✅ VPS stopped successfully!");

    println!();
    println!("🛑 VPS '{}' has been stopped", vm.name.bold());

    Ok(())
}

async fn handle_delete(client: &VPSClient, id: &str, force: bool) -> Result<()> {
    let vm = client.find_vm_by_name_or_id(id).await?;

    if !force {
        println!(
            "{}",
            "⚠️  WARNING: This action cannot be undone!".red().bold()
        );
        println!("VPS '{}' will be permanently deleted.", vm.name.bold());
        println!();

        let confirm = Confirm::new()
            .with_prompt("Are you absolutely sure you want to delete this VPS?")
            .default(false)
            .interact()?;

        if !confirm {
            println!("Operation cancelled");
            return Ok(());
        }
    }

    println!("Deleting VPS '{}'...", vm.name);

    let pb = ProgressBar::new_spinner();
    pb.set_style(
        ProgressStyle::default_spinner()
            .template("{spinner:.red} {msg}")
            .unwrap(),
    );
    pb.set_message("Deleting VM...");
    pb.enable_steady_tick(Duration::from_millis(100));

    client.delete_vm(&vm.id).await?;
    pb.finish_with_message("✅ VPS deleted successfully!");

    println!();
    println!("🗑️  VPS '{}' has been permanently deleted", vm.name.bold());

    Ok(())
}

async fn handle_health(client: &VPSClient) -> Result<()> {
    println!("Checking service health...");

    let pb = ProgressBar::new_spinner();
    pb.set_style(
        ProgressStyle::default_spinner()
            .template("{spinner:.blue} {msg}")
            .unwrap(),
    );
    pb.set_message("Connecting...");
    pb.enable_steady_tick(Duration::from_millis(100));

    let healthy = client.health_check().await?;
    pb.finish_and_clear();

    if healthy {
        println!("{}", "✅ Service is healthy and running".green());
    } else {
        println!("{}", "❌ Service is not responding".red());
        anyhow::bail!("Service health check failed");
    }

    Ok(())
}

async fn handle_console(client: &VPSClient) -> Result<()> {
    loop {
        println!();
        println!("{}", "🖥️  Firecracker VPS Management Console".bold().cyan());
        println!("─────────────────────────────────────────────");

        let actions = vec![
            "List VPS instances",
            "Create new VPS",
            "Start VPS",
            "Stop VPS",
            "Delete VPS",
            "Show VPS details",
            "Check service health",
            "Exit",
        ];

        let selection = Select::new()
            .with_prompt("Select an action")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                if let Err(e) = handle_list(client, false, None).await {
                    println!("{}: {}", "Error".red(), e);
                }
            }
            1 => {
                if let Err(e) = handle_create(client, None, 1, 512, 10, None, true).await {
                    println!("{}: {}", "Error".red(), e);
                }
            }
            2 => {
                let vms = client.list_vms().await.unwrap_or_default();
                if vms.is_empty() {
                    println!("{}", "No VPS instances found".yellow());
                    continue;
                }

                let vm_names: Vec<String> = vms
                    .iter()
                    .map(|vm| format!("{} ({})", vm.name, vm.id[..8].to_string()))
                    .collect();
                let vm_idx = Select::new()
                    .with_prompt("Select VPS to start")
                    .items(&vm_names)
                    .interact()?;

                if let Err(e) = handle_start(client, &vms[vm_idx].id, true).await {
                    println!("{}: {}", "Error".red(), e);
                }
            }
            3 => {
                let vms = client.list_vms().await.unwrap_or_default();
                if vms.is_empty() {
                    println!("{}", "No VPS instances found".yellow());
                    continue;
                }

                let vm_names: Vec<String> = vms
                    .iter()
                    .map(|vm| format!("{} ({})", vm.name, vm.id[..8].to_string()))
                    .collect();
                let vm_idx = Select::new()
                    .with_prompt("Select VPS to stop")
                    .items(&vm_names)
                    .interact()?;

                if let Err(e) = handle_stop(client, &vms[vm_idx].id, false).await {
                    println!("{}: {}", "Error".red(), e);
                }
            }
            4 => {
                let vms = client.list_vms().await.unwrap_or_default();
                if vms.is_empty() {
                    println!("{}", "No VPS instances found".yellow());
                    continue;
                }

                let vm_names: Vec<String> = vms
                    .iter()
                    .map(|vm| format!("{} ({})", vm.name, vm.id[..8].to_string()))
                    .collect();
                let vm_idx = Select::new()
                    .with_prompt("Select VPS to delete")
                    .items(&vm_names)
                    .interact()?;

                if let Err(e) = handle_delete(client, &vms[vm_idx].id, false).await {
                    println!("{}: {}", "Error".red(), e);
                }
            }
            5 => {
                let vms = client.list_vms().await.unwrap_or_default();
                if vms.is_empty() {
                    println!("{}", "No VPS instances found".yellow());
                    continue;
                }

                let vm_names: Vec<String> = vms
                    .iter()
                    .map(|vm| format!("{} ({})", vm.name, vm.id[..8].to_string()))
                    .collect();
                let vm_idx = Select::new()
                    .with_prompt("Select VPS to view details")
                    .items(&vm_names)
                    .interact()?;

                if let Err(e) = handle_get(client, &vms[vm_idx].id, false).await {
                    println!("{}: {}", "Error".red(), e);
                }
            }
            6 => {
                if let Err(e) = handle_health(client).await {
                    println!("{}: {}", "Error".red(), e);
                }
            }
            7 => {
                println!("Goodbye! 👋");
                break;
            }
            _ => unreachable!(),
        }

        println!();
        println!("Press Enter to continue...");
        std::io::stdin().read_line(&mut String::new()).ok();
    }

    Ok(())
}

fn format_status(status: &str) -> String {
    match status {
        "running" => status.green().to_string(),
        "stopped" => status.red().to_string(),
        "created" => status.yellow().to_string(),
        _ => status.to_string(),
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let client = VPSClient::new(cli.server.clone(), cli.verbose);

    // Check if service is accessible for most commands
    match &cli.command {
        Commands::Health => {} // Health check will handle its own connectivity
        _ => {
            if !client.health_check().await.unwrap_or(false) {
                eprintln!(
                    "{}: Cannot connect to Firecracker VPS service at {}",
                    "Error".red(),
                    cli.server
                );
                eprintln!("Make sure the service is running and the URL is correct.");
                std::process::exit(1);
            }
        }
    }

    match cli.command {
        Commands::Create {
            name,
            cpu,
            memory,
            disk,
            image,
            interactive,
        } => {
            handle_create(&client, name, cpu, memory, disk, image, interactive).await?;
        }
        Commands::List { detailed, status } => {
            handle_list(&client, detailed, status).await?;
        }
        Commands::Get { id, json } => {
            handle_get(&client, &id, json).await?;
        }
        Commands::Start { id, wait } => {
            handle_start(&client, &id, wait).await?;
        }
        Commands::Stop { id, force } => {
            handle_stop(&client, &id, force).await?;
        }
        Commands::Delete { id, force } => {
            handle_delete(&client, &id, force).await?;
        }
        Commands::Health => {
            handle_health(&client).await?;
        }
        Commands::Console => {
            handle_console(&client).await?;
        }
    }

    Ok(())
}
