# MongoDB Collection Count Checker

Simple script to check MongoDB collection counts for backup/restore verification.

## Purpose

When doing MongoDB backup and restore between environments, this script helps verify that all collections and documents were transferred correctly by counting them in both source and destination.

## Features

✅ **Automatic PRIMARY pod detection** - Finds and uses the primary MongoDB pod  
✅ **Complete collection counts** - Lists all databases, collections, and document counts  
✅ **Comprehensive logging** - All operations logged to file  
✅ **Works with replica sets and standalone MongoDB**  
✅ **Clean, simple output** - Easy to read and compare  
✅ **Simple manual comparison** - Use standard `diff` command

## Quick Start

### 1. Check Source Environment

```bash
# Run in source cluster
./mongodb_collection_checker.sh pe420-qa

# This creates: mongodb_counts_pe420-qa_20251030_143022.txt
```

### 2. Do Your Backup/Restore

```bash
# Perform your backup and restore operations...
```

### 3. Check Destination Environment

```bash
# Run in destination cluster
./mongodb_collection_checker.sh pe420-qa

# This creates: mongodb_counts_pe420-qa_20251030_151545.txt
```

### 4. Compare Results

```bash
# Simple comparison
diff mongodb_counts_pe420-qa_SOURCE*.txt mongodb_counts_pe420-qa_DEST*.txt

# No output = Perfect match! ✅
```

## Usage

```bash
./mongodb_collection_checker.sh <namespace> [pod-name]
```

### Arguments

- `namespace` - Required. Kubernetes namespace (e.g., `pe420-qa`)
- `pod-name` - Optional. Specific pod name. If not provided, PRIMARY pod is auto-detected

### Examples

```bash
# Auto-detect PRIMARY pod (recommended)
./mongodb_collection_checker.sh pe420-qa

# Use specific pod
./mongodb_collection_checker.sh pe420-qa mongodb-1

# Enable debug logging
DEBUG=1 ./mongodb_collection_checker.sh pe420-qa

# Help
./mongodb_collection_checker.sh --help
```

## Output

The script generates files in two directories:

1. **Count File**: `reports/mongodb_counts_<namespace>_YYYYMMDD_HHMMSS.txt`
   - Clean, simple format
   - All databases and collections with counts
   - Summary totals
   - Easy to compare with `diff`
   - Stored in `reports/` directory

2. **Log File**: `logs/mongodb_checker_YYYYMMDD_HHMMSS.log`
   - Detailed execution log
   - All operations with timestamps
   - Debug information
   - Stored in `logs/` directory

### Sample Output File

```
Namespace: pe420-qa | Pod: mongodb-0 | Role: PRIMARY | Date: 2025-10-30 14:30:22

Activity-pe420-qa:
  AuditTrail-2cf34db1-adbc-409b-a715-318f3f568d3a  = 224
  Locks                                             = 2
  [Total: 2 collections, 226 documents]

Catalog-pe420-qa:
  Locks                                             = 12
  Targets                                           = 0
  DBVERSION                                         = 1
  [Total: 3 collections, 13 documents]

Cluster-pe420-qa:
  PolicyGroup                                       = 3
  Locks                                             = 36
  GitUpstream                                       = 3
  PolicyGroupStatus                                 = 1
  DBVERSION                                         = 1
  ... (more collections)
  [Total: 35 collections, 44 documents]

Users-pe420-qa:
  Root                                              = 1
  Product                                           = 6
  Locks                                             = 2
  ... (more collections)
  [Total: 8 collections, 14 documents]

=========================================
SUMMARY:
  Total Databases:   7
  Total Collections: 92
  Total Documents:   422
=========================================
```

## How It Works

### 1. PRIMARY Pod Detection

The script automatically finds the PRIMARY MongoDB pod:

1. Searches for all MongoDB pods in the namespace
2. Connects to each pod and checks `rs.status()`
3. Identifies which pod has `stateStr === 'PRIMARY'`
4. Uses that pod for counting (most up-to-date data)

**Example console output:**
```
[INFO] Searching for PRIMARY MongoDB pod...
[INFO] Checking pod: mongodb-0
[INFO]   → Pod mongodb-0 is SECONDARY/ARBITER (skipping)
[INFO] Checking pod: mongodb-1
[SUCCESS] ✓ Found PRIMARY pod: mongodb-1
```

### 2. Collection Counting

For each database:
- Lists all collections
- Runs `countDocuments()` on each collection
- **Shows progress in real-time** so you know it's working
- Shows counts in simple format: `collection = count`
- Provides subtotal for each database

**Progress indicators you'll see:**
```
[INFO] Processing database [1]: Activity-pe420
[INFO]   → Found 12 collections, counting documents...
[INFO]   → Counting collection 5/12: AuditTrail
[INFO]   → Counting collection 10/12: Locks
[SUCCESS]   ✓ Completed Activity-pe420: 12 collections, 1,234 documents
```

### 3. File Generation

Creates a clean output file in `reports/` directory:
- Minimal header (one line)
- Database → Collection → Count
- Subtotals per database
- Overall summary

## Manual Comparison Methods

### Method 1: Simple Diff (Recommended)

```bash
diff mongodb_counts_source.txt mongodb_counts_dest.txt
```

- **No output** = Perfect match ✅
- **Shows differences** = Review what's different ⚠️

### Method 2: Side-by-Side Comparison

```bash
diff -y mongodb_counts_source.txt mongodb_counts_dest.txt | less
```

Shows files side-by-side with differences highlighted.

### Method 3: Just the Summaries

```bash
# Extract just the summary from each file
tail -6 mongodb_counts_source.txt
tail -6 mongodb_counts_dest.txt
```

Quick way to compare total counts.

### Method 4: Unified Diff with Context

```bash
diff -u mongodb_counts_source.txt mongodb_counts_dest.txt
```

Shows differences with surrounding context lines.

### Method 5: Visual Comparison

```bash
# Open both files in your editor
code mongodb_counts_source.txt mongodb_counts_dest.txt

# Or use vimdiff
vimdiff mongodb_counts_source.txt mongodb_counts_dest.txt
```

## Complete Backup/Restore Workflow

### Source Environment

```bash
# Switch to source cluster context
kubectl config use-context source-cluster

# Run collection count
./mongodb_collection_checker.sh pe420-qa

# Rename for clarity
mv mongodb_counts_pe420-qa_*.txt source_counts.txt
```

### Perform Backup & Restore

```bash
# Your backup commands here
# ...
# Your restore commands here
```

### Destination Environment

```bash
# Switch to destination cluster context
kubectl config use-context dest-cluster

# Run collection count
./mongodb_collection_checker.sh pe420-qa

# Rename for clarity
mv mongodb_counts_pe420-qa_*.txt dest_counts.txt
```

### Compare

```bash
# Compare the files
diff source_counts.txt dest_counts.txt

# If they match (no output):
echo "✅ Backup/Restore verified successfully!"

# If they differ:
echo "⚠️ Differences found - review needed"
diff -u source_counts.txt dest_counts.txt | less
```

## Troubleshooting

### No MongoDB pods found

```bash
# List all pods to find MongoDB
kubectl get pods -n pe420-qa | grep mongo

# If pod has different name, specify it:
./mongodb_collection_checker.sh pe420-qa <actual-pod-name>
```

### No PRIMARY found

If all pods are SECONDARY, election may be in progress:

```bash
# Check replica set status
kubectl exec -n pe420-qa mongodb-0 -- mongosh --eval "rs.status()"

# Wait 30 seconds and try again
sleep 30
./mongodb_collection_checker.sh pe420-qa
```

### Permission Issues

```bash
# Make script executable
chmod +x mongodb_collection_checker.sh

# Check kubectl access
kubectl auth can-i exec pods -n pe420-qa
```

### MongoDB Authentication Required

If your MongoDB requires authentication, you'll need to modify the script to add credentials to the `mongosh` commands.

## Tips

1. **Always run on PRIMARY** - Script does this automatically for accurate counts
2. **Run after restore completes** - Ensure restore process is fully finished
3. **Save count files** - Keep for audit trail and historical reference
4. **Check timestamps** - Verify counts are from correct time
5. **Maintenance window** - Best to run when database is not actively changing
6. **Use descriptive names** - Rename output files clearly (e.g., `source_counts.txt`, `dest_counts.txt`)

## File Management

### Generated Files

```bash
# Count files (keep these for comparison)
mongodb_counts_*.txt

# Logs (for troubleshooting)
logs/mongodb_checker_*.log
```

### Cleanup

```bash
# Remove old count files (keep last 10)
ls -t mongodb_counts_*.txt | tail -n +11 | xargs rm -f

# Remove old logs (older than 7 days)
find logs/ -name "*.log" -mtime +7 -delete
```

## Understanding Your Output

### For pe420-qa namespace:

Your databases follow the pattern: `<name>-pe420-qa`

Example databases:
- `Activity-pe420-qa`
- `Catalog-pe420-qa`
- `Cluster-pe420-qa`
- `Config-pe420-qa`
- `Environments-pe420-qa`
- `Policies-pe420-qa`
- `Users-pe420-qa`

### What the counts mean:

```
Activity-pe420-qa:
  AuditTrail-xxx  = 224    ← 224 documents in AuditTrail collection
  Locks           = 2      ← 2 documents in Locks collection
  [Total: 2 collections, 226 documents]  ← Database total
```

If after restore you see:
```
Activity-pe420-qa:
  AuditTrail-xxx  = 224    ← ✅ Match
  Locks           = 2      ← ✅ Match
  [Total: 2 collections, 226 documents]  ← ✅ Match
```

Then backup/restore was successful for this database!

## FAQ

**Q: Why detect PRIMARY pod?**  
A: PRIMARY has the most current data in a replica set. Secondaries may lag slightly.

**Q: How long does it take?**  
A: Depends on database size. Usually 10 seconds to a few minutes.

**Q: Does it affect MongoDB performance?**  
A: `countDocuments()` is read-only but may have minor impact on very large collections.

**Q: Can I run on SECONDARY?**  
A: Yes, specify the pod name explicitly: `./mongodb_collection_checker.sh pe420-qa mongodb-0`

**Q: What MongoDB versions are supported?**  
A: Tested with MongoDB 5.0+. Uses `mongosh` (modern MongoDB shell).

**Q: What if I have empty collections?**  
A: They'll show as `collection = 0` which is fine - they're still counted.

**Q: How do I know if collections match?**  
A: Use `diff` - no output means perfect match!

## Support

For issues:
1. Check log file in `logs/` directory
2. Run with `DEBUG=1` for verbose output
3. Verify kubectl access and MongoDB connectivity
4. Check that MongoDB pods are running: `kubectl get pods -n <namespace>`
