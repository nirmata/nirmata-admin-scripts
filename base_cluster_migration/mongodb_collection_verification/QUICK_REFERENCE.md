# Quick Reference

## Basic Usage

```bash
# Check collection counts (auto-detects PRIMARY)
./mongodb_collection_checker.sh pe420-qa
```

## Complete Backup/Restore Verification

### Step 1: Source Environment
```bash
kubectl config use-context source-cluster
./mongodb_collection_checker.sh pe420-qa
mv reports/mongodb_counts_pe420-qa_*.txt source_counts.txt
```

### Step 2: Backup & Restore
```bash
# Do your backup/restore here
```

### Step 3: Destination Environment
```bash
kubectl config use-context dest-cluster
./mongodb_collection_checker.sh pe420-qa
mv reports/mongodb_counts_pe420-qa_*.txt dest_counts.txt
```

### Step 4: Compare
```bash
diff source_counts.txt dest_counts.txt

# No output = Perfect match ✅
# Shows differences = Review needed ⚠️
```

## Progress Indicators

The script shows real-time progress so you know it's working:

```
[INFO] Processing database [1]: Activity-pe420
[INFO]   → Found 12 collections, counting documents...
[INFO]   → Counting collection 5/12: AuditTrail
[SUCCESS]   ✓ Completed Activity-pe420: 12 collections, 1,234 documents
```

**Note**: For databases with many collections, progress shows every 5 collections to avoid overwhelming output.

## Output File Format

**Filename**: `reports/mongodb_counts_<namespace>_YYYYMMDD_HHMMSS.txt`

**Content**:
```
Namespace: pe420-qa | Pod: mongodb-0 | Role: PRIMARY | Date: 2025-10-30 14:30:22

Activity-pe420-qa:
  AuditTrail-xxx  = 224
  Locks           = 2
  [Total: 2 collections, 226 documents]

Catalog-pe420-qa:
  Locks           = 12
  Targets         = 0
  DBVERSION       = 1
  [Total: 3 collections, 13 documents]

=========================================
SUMMARY:
  Total Databases:   7
  Total Collections: 92
  Total Documents:   422
=========================================
```

## Comparison Methods

```bash
# Simple diff (recommended)
diff source_counts.txt dest_counts.txt

# Side-by-side view
diff -y source_counts.txt dest_counts.txt

# With context
diff -u source_counts.txt dest_counts.txt

# Just summaries
tail -6 source_counts.txt
tail -6 dest_counts.txt

# Visual comparison
code source_counts.txt dest_counts.txt
```

## Common Commands

```bash
# Basic check
./mongodb_collection_checker.sh pe420-qa

# Specific pod
./mongodb_collection_checker.sh pe420-qa mongodb-1

# Debug mode
DEBUG=1 ./mongodb_collection_checker.sh pe420-qa

# Help
./mongodb_collection_checker.sh --help
```

## Output Files

```
reports/mongodb_counts_<namespace>_YYYYMMDD_HHMMSS.txt  # Collection count file
logs/mongodb_checker_YYYYMMDD_HHMMSS.log                # Execution log
```

## Quick Troubleshooting

```bash
# Make executable
chmod +x mongodb_collection_checker.sh

# Find pods
kubectl get pods -n pe420-qa | grep mongo

# Check replica set
kubectl exec -n pe420-qa mongodb-0 -- mongosh --eval "rs.status()"

# Check PRIMARY
kubectl exec -n pe420-qa mongodb-0 -- mongosh --eval "db.isMaster()"
```

## One-Liner Workflows

### Quick Comparison
```bash
# Source
./mongodb_collection_checker.sh pe420-qa && mv mongodb_counts_*.txt /tmp/source.txt

# Destination  
./mongodb_collection_checker.sh pe420-qa && mv mongodb_counts_*.txt /tmp/dest.txt

# Compare
diff /tmp/source.txt /tmp/dest.txt && echo "✅ MATCH" || echo "⚠️ DIFFERENT"
```

### With Date in Filename
```bash
# Source
./mongodb_collection_checker.sh pe420-qa
mv mongodb_counts_pe420-qa_*.txt source_$(date +%Y%m%d).txt

# Destination
./mongodb_collection_checker.sh pe420-qa
mv mongodb_counts_pe420-qa_*.txt dest_$(date +%Y%m%d).txt

# Compare
diff source_*.txt dest_*.txt
```

## File Cleanup

```bash
# Keep last 5 count files
ls -t mongodb_counts_*.txt | tail -n +6 | xargs rm -f

# Clean old logs (7+ days)
find logs/ -name "*.log" -mtime +7 -delete

# Clean all generated files
rm -f mongodb_counts_*.txt
rm -rf logs/
```

## Understanding Output

### Database Names
Your databases: `<name>-<namespace>`

Example for `pe420-qa`:
- `Activity-pe420-qa`
- `Catalog-pe420-qa`
- `Cluster-pe420-qa`
- `Config-pe420-qa`
- `Environments-pe420-qa`
- `Policies-pe420-qa`
- `Users-pe420-qa`

### Collection Counts
```
Database-name:
  collection1  = 100   ← 100 documents
  collection2  = 50    ← 50 documents
  [Total: 2 collections, 150 documents]
```

### What to Compare
```
SOURCE:                    DESTINATION:
Activity-pe420-qa:         Activity-pe420-qa:
  Locks = 2                  Locks = 2           ✅ Match
  [Total: 2, 226]            [Total: 2, 226]     ✅ Match
```

## Common Scenarios

### Scenario 1: Perfect Restore
```bash
$ diff source.txt dest.txt
(no output)
$ echo "✅ Perfect restore!"
```

### Scenario 2: Missing Documents
```bash
$ diff source.txt dest.txt
< Activity-pe420-qa: Locks = 224
---
> Activity-pe420-qa: Locks = 200
```
⚠️ Destination has fewer documents

### Scenario 3: Missing Collections
```bash
$ diff source.txt dest.txt
< Products = 100
```
⚠️ Collection missing in destination

### Scenario 4: Extra Data
```bash
$ diff source.txt dest.txt
> NewCollection = 50
```
⚠️ Extra collection in destination (investigate)

## Tips

1. **Run script AFTER restore completes**
2. **Save both count files** with descriptive names
3. **No diff output = success!**
4. **Keep logs** for troubleshooting
5. **Use during maintenance windows** for stable counts
6. **Compare summaries first** for quick validation
7. **Check timestamps** to ensure recent counts

## Quick Validation Checklist

- [ ] Script completed successfully
- [ ] Output file created
- [ ] All databases listed
- [ ] Summary shows total counts
- [ ] Ran on both source and destination
- [ ] Compared with diff
- [ ] No differences found (or reviewed differences)
- [ ] Saved files for audit trail

## Example Session

```bash
# Start
$ ./mongodb_collection_checker.sh pe420-qa

[INFO] MongoDB Collection Count Checker
[INFO] Searching for PRIMARY MongoDB pod...
[SUCCESS] ✓ Found PRIMARY pod: mongodb-1
[INFO] Target: pe420-qa/mongodb-1
[SUCCESS] Pod mongodb-1 is Running
[INFO] Fetching databases and collections...
[INFO] Processing database [1]: Activity-pe420-qa
[INFO] Processing database [2]: Catalog-pe420-qa
...
[SUCCESS] ✓ Collection count completed!
[SUCCESS] 📄 Output file: mongodb_counts_pe420-qa_20251030_143022.txt
[INFO] Summary: 7 databases, 92 collections, 422 documents

# Check the file
$ cat mongodb_counts_pe420-qa_20251030_143022.txt
Namespace: pe420-qa | Pod: mongodb-1 | Role: PRIMARY | Date: 2025-10-30 14:30:22
...

# Compare
$ diff source.txt dest.txt
(no output)

$ echo "✅ Backup/Restore verified!"
✅ Backup/Restore verified!
```
