# Nirmata Services Log Collection Script

This script is designed to collect logs from multiple Nirmata services running in a Kubernetes cluster.

## Prerequisites

- The script uses the kubeconfig from `/root/.kube/config` and switches the context to the base cluster.
- Ensure that `kubectl` and `curl` are installed and properly configured on the system running this script.

## Usage

```bash
./collect-nirmata-services-logs.sh <NirmataURL> <Namespace> <LogDurationInMinutes> <Nirmata-service1> <Nirmata-service2> ...
```

### Examples:

#### Single Service Example:
```bash
./collect-nirmata-services-logs.sh https://www.nirmata.io nirmata 10 config
```

#### Multiple Services Example:
```bash
./collect-nirmata-services-logs.sh https://www.nirmata.io nirmata 10 config cluster-processor environments
```

### Nirmata Services:
- `activity`
- `catalog`
- `cluster`
- `config`
- `environments`
- `users`

> **Note:** Replace `<NirmataURL>`, `<Namespace>`, `<LogDurationInMinutes>`, and the service names (`<Nirmata-service1>`, `<Nirmata-service2>`, etc.) with the appropriate values based on your environment.

## Script Behavior

- **Log Duration:** The script captures logs for the specified duration (in minutes) for each Nirmata service provided.
- **Log File Naming:** Logs are saved in the current directory with names in the format: `<Nirmata-service>-YYYY-MM-DD_HH-MM-SS.log`.
- **Zipping Logs:** After collecting logs for all specified services, the script compresses them into a zip file named `nirmata-logs-YYYY-MM-DD_HH-MM-SS.zip`.
- **Sharing:** The logs are saved in the current directory. Please share the zip file via JIRA or Email.

## Example Output

```bash
Collecting logs of gateway-service-64ff87596f-cjbpc for 10 minutes and saving in file named 'gateway-service-2024-08-14_14-45-30.log'
```
