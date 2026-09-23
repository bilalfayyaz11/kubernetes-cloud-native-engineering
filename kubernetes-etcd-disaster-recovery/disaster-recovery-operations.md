# Kubernetes etcd Disaster Recovery Operations

## Backup Procedure

Run:

```bash
sudo /opt/etcd-backup/backup-etcd.sh
```

The backup workflow performs:

1. etcd endpoint health validation
2. live snapshot creation with etcdctl
3. snapshot validation with etcdutl
4. SHA256 checksum generation
5. snapshot metadata capture
6. seven-day retention cleanup

## Snapshot Files

Each backup produces:

```text
etcd-backup-YYYYMMDD_HHMMSS.db
etcd-backup-YYYYMMDD_HHMMSS.db.sha256
etcd-backup-YYYYMMDD_HHMMSS.db.metadata
```

## Snapshot Validation

Validate a snapshot before recovery:

```bash
sudo etcdutl snapshot status /opt/etcd-backup/<snapshot>.db
```

Verify its checksum:

```bash
cd /opt/etcd-backup
sudo sha256sum -c <snapshot>.db.sha256
```

## Restore Procedure

The reusable restore utility intentionally requires explicit confirmation.

Run:

```bash
sudo ETCD_RESTORE_CONFIRM=YES \
  /opt/etcd-backup/restore-etcd.sh \
  /opt/etcd-backup/<snapshot>.db
```

The restore procedure:

1. validates the snapshot
2. validates its checksum when available
3. preserves the currently active datastore
4. stops kube-apiserver
5. stops etcd
6. restores into a new datastore directory
7. applies revision bump and compaction marking
8. updates the etcd static Pod hostPath
9. starts the restored etcd member
10. verifies etcd endpoint health
11. restarts kube-apiserver
12. validates Kubernetes API recovery

## Recovery Safety Model

The currently active datastore is not deleted.

Restored data is written into a separate directory such as:

```text
/var/lib/etcd-restored-YYYYMMDD_HHMMSS
```

This preserves the previous datastore as an additional recovery path.

## Retention

Automated snapshots are retained for seven days.

Older snapshot database files, checksums, and metadata files are removed automatically by the backup script.
