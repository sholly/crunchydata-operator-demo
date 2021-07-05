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


Scale cluster to 2: 

`pgo -n pgo scale test --replica-count=2`


Test cluster availability: 

`pgo -n pgo test hacluster`


Creating backups: 

Full: 

`pgo -n pgo backup test --backup-opts="--type=full"`

Incremental: 

`pgo -n pgo backup test --backup-opts="--type=incr"`


Show backups: 

`pgo -n pgo show backup test`

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

Create new cluster from old cluster's data: 

`pgo create cluster -n pgo test2 -u test --password password --restore-from=test`


