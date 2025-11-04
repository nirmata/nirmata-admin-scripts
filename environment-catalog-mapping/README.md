# Environment to Catalog Mapping Tools

This folder contains scripts to analyze environments and their relationships to catalogs in Nirmata, helping identify manual mapping opportunities for application migration.

## Scripts Available

### 1. `get_env_catalog_mapping.sh` - General Environment-Catalog Analysis
Provides visibility into environment-to-catalog relationships for migration planning.

### 2. `cross_cluster_catalog_mapping.sh` - Cross-Cluster Catalog Mapping
**NEW!** Specifically designed for mapping catalogs from source cluster environments to destination cluster environments after migration.

## Purpose

These scripts provide:
- Environment-to-catalog relationships
- Application counts in environments and catalogs
- Mapping recommendations for migration planning
- Cross-cluster catalog linking guidance
- Support for both single-environment and cross-environment scenarios

## Usage

### Script 1: General Environment-Catalog Analysis (`get_env_catalog_mapping.sh`)

#### Single Cluster Analysis
Analyze environments vs catalogs within the same Nirmata instance:
```bash
./get_env_catalog_mapping.sh <API_ENDPOINT> <API_TOKEN> <CLUSTER_NAME>
```

#### Same Environment Cross-Cluster
Map between clusters in the same Nirmata instance:
```bash
./get_env_catalog_mapping.sh <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER>
```

#### Cross Environment Migration
Map between clusters in different Nirmata instances:
```bash
./get_env_catalog_mapping.sh <SOURCE_API> <SOURCE_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER> <DEST_API> <DEST_TOKEN>
```

### Script 2: Cross-Cluster Catalog Mapping (`cross_cluster_catalog_mapping.sh`)

**Perfect for post-migration catalog linking:**
```bash
./cross_cluster_catalog_mapping.sh <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER>
```

**Use Case:** After migrating environments from source cluster to destination cluster, this script identifies which catalogs need to be manually linked to the new environments.

## Examples

```bash
# Single cluster analysis
./get_env_catalog_mapping.sh https://pe420.nirmata.co "API_TOKEN" n4k-rollout

# Same environment cross-cluster
./get_env_catalog_mapping.sh https://pe420.nirmata.co "API_TOKEN" source-cluster dest-cluster

# Cross environment migration
./get_env_catalog_mapping.sh https://source.nirmata.co "SOURCE_TOKEN" source-cluster dest-cluster https://dest.nirmata.co "DEST_TOKEN"

# Cross-cluster catalog mapping (NEW!)
./cross_cluster_catalog_mapping.sh https://pe420.nirmata.co "API_TOKEN" n4k-rollout new-rhel
```

## Cross-Cluster Catalog Mapping Output

The `cross_cluster_catalog_mapping.sh` script provides:

**CSV Output Example:**
```csv
Source Environment,Source Env ID,Source Apps,Catalog Name,Catalog ID,Catalog Apps,Dest Environment,Dest Env ID,Dest Apps,Mapping Action,Manual Steps
nirmata-n4k-rollout,25deecc8-69fc-479f-92f8-627233e18f23,1,nirmata,72cf930f-53f9-4950-93cd-3b315aba3239,0,nirmata-new-rhel,cbf27a2d-05cc-4242-8cf6-8450b3b4043a,1,LINK_CATALOG,Use Catalog ID 72cf930f-53f9-4950-93cd-3b315aba3239 to link to Dest Env ID cbf27a2d-05cc-4242-8cf6-8450b3b4043a
```

**Key Actions:**
- **LINK_CATALOG:** Ready for immediate manual linking
- **CREATE_ENV_FIRST:** Create destination environment first
- **NO_CATALOG_FOUND:** Find/create appropriate catalog
- **NO_DEST_ENV_NO_CATALOG:** Complete manual setup required

## Output Files

The script generates two types of output:

### 1. Detailed CSV Report
**Format:** `{cluster}_environment_catalog_mapping_{timestamp}.csv`

Contains:
- Environment Name and ID
- Application counts per environment
- Mapped catalog information
- Mapping status and recommendations

### 2. Summary Report
**Format:** `{cluster}_catalog_mapping_summary_{timestamp}.txt`

Contains:
- Statistical summary
- Mapping status breakdown
- Next steps recommendations

## Mapping Status Types

| Status | Description |
|--------|-------------|
| **Exact Match** | Environment name matches catalog name exactly |
| **Potential Match** | Environment name similar to catalog (cluster suffix removed) |
| **Needs Review** | Partial matches found, manual review required |
| **No Match** | No matching catalog found |
| **Ready for Migration** | (Cross-cluster) Complete mapping available |
| **Create Catalog** | (Cross-cluster) Destination environment exists, catalog needed |
| **Create Environment** | (Cross-cluster) Catalog exists, destination environment needed |
| **Manual Setup Required** | (Cross-cluster) Both destination environment and catalog needed |

## Sample Output

```csv
Environment Name,Environment ID,Applications Count,Catalog Name,Catalog ID,Catalog Apps Count,Mapping Status,Notes
nirmata-n4k-rollout,25deecc8-69fc-479f-92f8-627233e18f23,1,nirmata,72cf930f-53f9-4950-93cd-3b315aba3239,0,Potential Match,Environment name similar to catalog name (nirmata)
kyverno,54517c97-0b70-40c3-bcaa-28d768c42a2a,1,N/A,N/A,N/A,Needs Review,Possible matches found: kyverno-n4k
```

## Integration with Migration Scripts

This mapping tool is designed to work with existing migration scripts:

1. **Use mapping results** to identify environments ready for migration
2. **Reference Environment IDs and Catalog IDs** for manual mapping
3. **Run migration scripts** from other folders:
   - `../ndp_application_migration/` - Application migration tools
   - `../cross_environment_migration/` - Cross-environment migration workflows

## Prerequisites

- `curl` installed
- `jq` installed for JSON processing
- Valid Nirmata API tokens
- Appropriate permissions to access environments and catalogs

## API References

The script uses the following Nirmata APIs:
- `/environments/api/clusters` - List clusters
- `/environments/api/environments` - List environments
- `/environments/api/environments/{id}/applications` - Environment applications
- `/catalog/api/catalogs` - List catalogs
- `/catalog/api/applications` - Catalog applications

## Error Handling

The script includes comprehensive error handling:
- API authentication validation
- JSON response validation
- Cluster and environment existence checks
- Detailed logging for troubleshooting

## Notes

- The script intelligently removes cluster suffixes from environment names when matching to catalogs
- Cross-environment scenarios support different API endpoints and tokens
- All API calls are logged for debugging purposes
- Generated files include timestamps to avoid conflicts

