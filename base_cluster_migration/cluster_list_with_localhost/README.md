# Cluster Localhost Detection Script

This script identifies Kubernetes clusters in Nirmata that have `localhost` or `127.0.0.1` in their kubeconfig API server URL and generates a CSV report for migration planning.

## Overview

When clusters are registered with Nirmata using local kubeconfig files, they often contain `localhost` or `127.0.0.1` as the API server endpoint. This script:
- Fetches all clusters from your Nirmata account
- Checks each cluster's kubeconfig for localhost references
- Retrieves the real API server endpoint from cluster configuration
- Generates a CSV report for easy review and migration planning

## Prerequisites

- `curl` - HTTP client
- `jq` - JSON processor (install via `brew install jq` on macOS or `apt-get install jq` on Linux)
- Valid Nirmata API token

## Getting Your API Token

1. Login to Nirmata
2. Navigate to **Settings** → **Account** → **Generate API Key**
3. Copy the generated API key

## Usage

```bash
./check_localhost_clusters.sh <nirmata_url> <api_token>
```

### Parameters

- `nirmata_url` - Your Nirmata instance URL (e.g., `https://www.nirmata.io` or `https://staging.nirmata.co`)
- `api_token` - Your Nirmata API token

### Example

```bash
./check_localhost_clusters.sh https://www.nirmata.io EjJwbMsN9gtYD7nmFFMY4sVKPo3kHa5ggDjH4+FM1HjOymh9ZmR8NHeUzWy2EjwGkVzDOe0ezvenhFy7G4tmQw==
```

## Output

The script generates a timestamped CSV file: `localhost_clusters_YYYYMMDD_HHMMSS.csv`

### CSV Columns

| Column | Description |
|--------|-------------|
| Cluster Name | Name of the cluster in Nirmata |
| Cluster ID | Unique identifier for the cluster |
| Kubeconfig API Server | Current API server URL from kubeconfig (may contain localhost) |
| Real API Server Endpoint | Actual API endpoint configured in Nirmata cluster settings |
| Has Localhost | Yes/No flag indicating if cluster uses localhost |

### Sample Output

```
Cluster Name,Cluster ID,Kubeconfig API Server,Real API Server Endpoint,Has Localhost
"eks-manag","6e535bb8-...","https://B5D70E44...amazonaws.com","https://B5D70E44...amazonaws.com","No"
"kind-01","0dded0cb-...","https://localhost:6443","","Yes"
"kind-06","fe010215-...","https://127.0.0.1:60854","","Yes"
```

### Console Output

The script provides real-time progress:

```
Fetching Environment Root ID...
Fetching all clusters from Nirmata...
URL: https://www.nirmata.io
Environment ID: 228c7b65-50cd-4539-b129-fe8d056f274d
================================================
Found clusters. Processing...

[1] Processing: eks-manag... [Remote]
[2] Processing: kind-01... [LOCALHOST]
[3] Processing: kind-06... [LOCALHOST]
...

================================================
SUMMARY
================================================
Total clusters checked: 28
Clusters with localhost: 18
Clusters with remote URLs: 10

Results saved to: localhost_clusters_20251030_135318.csv
```

## Migration Planning

Use the CSV report to:

1. **Identify affected clusters**: Look for rows where "Has Localhost" = "Yes"
2. **Find replacement endpoints**: Check the "Real API Server Endpoint" column
3. **Update kubeconfigs**: Replace localhost URLs with real endpoints
4. **Empty endpoint values**: For clusters with empty "Real API Server Endpoint", you'll need to:
   - Check the cluster details in Nirmata UI
   - Verify the actual Kubernetes API server endpoint
   - Update the cluster configuration in Nirmata

## Troubleshooting

### jq not found

Install jq:
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt-get install jq`
- CentOS/RHEL: `sudo yum install jq`

### Authentication Error (401)

- Verify your API token is correct
- Generate a new API token from Nirmata Settings
- Ensure the token has appropriate permissions

### Empty Results

- Verify you have clusters registered in Nirmata
- Check that the Nirmata URL is correct
- Ensure your API token has access to view clusters

## API Authentication

The script uses Nirmata's API authentication format:

```
Authorization: NIRMATA-API <your-api-key>
```

## Notes

- The script automatically detects the Environment Root ID
- All clusters under your account are scanned
- The CSV file can be opened in Excel or any spreadsheet application
- Generated CSV files are timestamped to avoid overwriting previous reports

## Support

For issues or questions, contact Nirmata Support or your Nirmata administrator.

