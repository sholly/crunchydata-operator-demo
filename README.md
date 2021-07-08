create namespace pgo

install operator via console

oc edit cm pgo-config
find pgo.yaml section
add DisableFSGroup: true

Scale down then up for changes to take effect. 

```
oc -n pgo scale --replicas 0 deployment/postgres-operator
oc -n pgo scale --replicas 1 deployment/postgres-operator
```

Set up the pgo client: 

```
curl https://raw.githubusercontent.com/CrunchyData/postgres-operator/v4.6.2/deploy/install-bootstrap-creds.sh > install-bootstrap-creds.sh
curl https://raw.githubusercontent.com/CrunchyData/postgres-operator/v4.6.2/installers/kubectl/client-setup.sh > client-setup.sh

chmod +x install-bootstrap-creds.sh client-setup.sh

export PGO_OPERATOR_NAMESPACE=pgo

PGO_CMD=oc ./install-bootstrap-creds.sh
PGO_CMD=oc ./client-setup.sh

```

Add exports to bashrc: 

```
export PATH=/home/jshollen/.pgo/pgo:$PATH
export PGOUSER=/home/jshollen/.pgo/pgo/pgouser
export PGO_CA_CERT=/home/jshollen/.pgo/pgo/client.crt
export PGO_CLIENT_CERT=/home/jshollen/.pgo/pgo/client.crt
export PGO_CLIENT_KEY=/home/jshollen/.pgo/pgo/client.key
```

Expose the api endpoint: 

```
oc -n pgo expose deployment postgres-operator
oc -n pgo create route passthrough postgres-operator --service=postgres-operator
```

export apiserver url: 

`export PGO_APISERVER_URL="https://$(oc -n "$PGO_OPERATOR_NAMESPACE" get route postgres-operator -o jsonpath="{.spec.host}")"`


Create cluster: 

```
pgo create cluster -n pgo test -u test -p password

created cluster: test
workflow id: 45c136ae-6b2c-4ac9-b0a3-407e38108f7a
database name: test
users:
	username: test password: password
```

Alternatively, create a cluster with a specified database, as well as specifying 
the volume sizes for the database pvcs as well as the pg_backrest pvc: 

```
pgo create cluster test \
  -u test \
  --password password \
  -d todo \
  --pgbackrest-pvc-size=10Gi\ 
  --pvc-size=5Gi
```

Show status of cluster: 
`pgo -n pgo show workflow $workflow_id`


Add data to cluster: 

```
oc -n pgo port-forward svc/test 5432:5432 &
```

In separate terminal: 
```
psql -h localhost -U test test
test=> \i todo.openshift.sql 
```


Test cluster availability: 

`pgo -n pgo test hacluster`


## Creating backups: 

### Full: 

`pgo -n pgo backup test --backup-opts="--type=full"`

### Incremental: 

`pgo -n pgo backup test --backup-opts="--type=incr"`

### Logical backups with 'pgdump' 

`pgo backup test --backup-type=pgdump`


### Show backups: 

`pgo -n pgo show backup test`

### Scheduling backups

Schedule full backup once a day at midnight, keeping 21 backups: 

```
pgo -n pgo create schedule test --schedule="0 1 * * *" \
  --schedule-type=pgbackrest  --pgbackrest-backup-type=full \
  --schedule-opts="--repo1-retention-full=21"

```

Schedule incremental backup every 3 hours: 

```
pgo -n pgo create schedule test --schedule="0 */3 * * *" \
  --schedule-type=pgbackrest  --pgbackrest-backup-type=incr
```


### Where are backups stored? 


For 'pgbackrest' backups, there is a volume created for every cluster created.  

The 'test' cluster, for example, has an associated PersistentVolumeClaim named 'test-pgbr-repo'

On my personal cluster, the 'test-pgbr-repo' PVC is backed by nfs, namely '/nfs/vol8' on the NFS server.  

Examining '/nfs/vol8/test-backrest-shared-repo/backup/db', we see the following: 

```
drwxr-x---. 3 1000710000 root   72 Jul  7 17:21 20210707-212131F
drwxr-x---. 3 1000710000 root   72 Jul  7 17:57 20210707-215725F
drwxr-x---. 3 1000710000 root   18 Jul  7 17:21 backup.history
-rw-r-----. 1 1000710000 root 1548 Jul  7 17:57 backup.info
-rw-r-----. 1 1000710000 root 1548 Jul  7 17:57 backup.info.copy
lrwxrwxrwx. 1 1000710000 root   16 Jul  7 17:57 latest -> 20210707-215725F

```
For pgdump logical backups for the 'test' cluster, the operator creates a separate PVC 
named 'backup-test-pgdump-postgres-pvc'

### Restoring from a full backup: 

Create a full backup: 
`pgo -n pgo backup test --backup-opts="--type=full"`

Drop table todoitems: 

```
oc -n pgo port-forward svc/test 5432:5432 &
psql -h localhost -U test test

test=> drop table todoitems;
```

Find the timestamp to restore to: 

```
$ pgo show backup test

cluster: test
storage type: posix

stanza: db
    status: ok
    cipher: none

    db (current)
        wal archive min/max (13-1)
...output omitted for brevity...

            backup reference list: 20210707-230030F, 20210707-230030F_20210707-233109I

        full backup: 20210707-234032F
            timestamp start/stop: 2021-07-07 17:40:32 -0600 MDT / 2021-07-07 17:40:46 -0600 MDT
            wal start/stop: 000000030000000000000016 / 000000030000000000000016
            database size: 31.1MiB, backup size: 31.1MiB
            repository size: 3.8MiB, repository backup size: 3.8MiB
            backup reference list: 
```

We will restore from timestamp ''

`pgo restore test  --pitr-target="2021-07-07 17:40:46" --backup-opts="--type=time"

This will take some time, as it will delete and recreate the primary database pod as well as all its replicas.  
### Restoring from a logical backup

Drop table todoitems: 

```
oc -n pgo port-forward svc/test 5432:5432 &
psql -h localhost -U test test

test=> drop table todoitems;
```


Now restore: 


We need the pgdump pvc name: 

`pgo show backup test --backup-type=pgdump`

Gives us: 

```
pgdump : backup-test-pgdump
	PVC Name:	backup-test-pgdump-postgres-pvc
	Access Mode:	ReadWriteOnce
	PVC Size:	1G
	Creation:	2021-07-07 23:11:21 +0000 UTC
	CCPImageTag:	ubi8-13.2-4.6.2
	Backup Status:	job completed [backup-test-pgdump-whuh]
	Backup Host:	test
	Backup User Secret:	test-postgres-secret
	Backup Port:	5432
	Backup Opts:	--dump-all 

```

We will unfortunately need the specific timestap from the 'test-backups' directory.  
In this case, the backup directory timestamp is '2021-07-07-23-11-25'

Now restore from the pgdump backup: 
`pgo restore test --backup-type=pgdump --backup-pvc=backup-test-pgdump-postgres-pvc --pitr-target="2021-07-07-23-11-25" -n pgo`



## Scaling clusters

### Scaling up
Scale cluster to 3: 

`pgo -n pgo scale test --replica-count=3`

View the replicas: 

```
$ pgo show cluster test

cluster : test (crunchy-postgres-ha:ubi8-13.2-4.6.2)
	pod : test-7dd96bbd64-jgz8b (Running) on app1 (1/1) (primary)
		pvc: test (5Gi)
	pod : test-lxzh-5b698c5fdc-6k9bx (Running) on app1 (1/1) (replica)
		pvc: test-lxzh (5Gi)
	pod : test-meub-65d5476f9d-vm7qp (Running) on infra1 (1/1) (replica)
		pvc: test-meub (5Gi)
	pod : test-rvhg-8ddf4c75d-jttgq (Running) on infra2 (1/1) (replica)
		pvc: test-rvhg (5Gi)
	resources : Memory: 128Mi
	deployment : test
	deployment : test-backrest-shared-repo
	deployment : test-lxzh
	deployment : test-meub
	deployment : test-rvhg
	service : test - ClusterIP (172.30.248.12) - Ports (2022/TCP, 5432/TCP)
	service : test-replica - ClusterIP (172.30.18.136) - Ports (2022/TCP, 5432/TCP)
	pgreplica : test-lxzh
	pgreplica : test-meub
	pgreplica : test-rvhg
	labels : name=test pg-cluster=test pgo-version=4.6.2 pgouser=admin workflowid=32116c84-cbbc-4631-b8df-14a94eb5c0b0 crunchy-pgha-scope=test deployment-name=test 

```

We can also view replicas via 

```
$ pgo failover --query test
REPLICA             	STATUS    	NODE      	REPLICATION LAG     	PENDING RESTART
test-lxzh           	running   	app1      	           0 MB     	          false
test-meub           	running   	infra1    	           0 MB     	          false
test-rvhg           	running   	infra2    	           0 MB     	          false
```


### Manual failover to a replica
If there is a time when we want to manually fail over the cluster, we can do so via 

`pgo failover test --target=test-rvhg`


Verify our primary now points to test-rvhg:

```
cluster : test (crunchy-postgres-ha:ubi8-13.2-4.6.2)
	pod : test-7dd96bbd64-jgz8b (Running) on app1 (1/1) (replica)
		pvc: test (5Gi)
	pod : test-lxzh-5b698c5fdc-6k9bx (Running) on app1 (1/1) (replica)
		pvc: test-lxzh (5Gi)
	pod : test-meub-65d5476f9d-vm7qp (Running) on infra1 (1/1) (replica)
		pvc: test-meub (5Gi)
	pod : test-rvhg-8ddf4c75d-jttgq (Running) on infra2 (1/1) (primary)
		pvc: test-rvhg (5Gi)
	resources : Memory: 128Mi
	deployment : test
	deployment : test-backrest-shared-repo
	deployment : test-lxzh
	deployment : test-meub
	deployment : test-rvhg
	service : test - ClusterIP (172.30.248.12) - Ports (2022/TCP, 5432/TCP)
	service : test-replica - ClusterIP (172.30.18.136) - Ports (2022/TCP, 5432/TCP)
	pgreplica : test-lxzh
	pgreplica : test-meub
	pgreplica : test-rvhg
	labels : crunchy-pgha-scope=test deployment-name=test-rvhg name=test pg-cluster=test pgo-version=4.6.2 pgouser=admin workflowid=32116c84-cbbc-4631-b8df-14a94eb5c0b0 
```

We can point back to our primary via: 

`pgo failover test --target=test`

### Destroying a replica

Find the target replica via the scaledown command, then scale it down: 

```
pgo scaledown test --query
pgo scaledown test --target=test-lxzh

```

### Cloning a cluster: 

`pgo create cluster newtest --restore-from=test`