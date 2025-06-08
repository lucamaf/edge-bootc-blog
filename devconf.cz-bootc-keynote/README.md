# Running the second demo at devconf.cz keynote 2025

Install kind and kubectl cli tools.

Deploy kind on a system in rootless mode with:

`$ systemd-run --scope --user -p "Delegate=yes" kind create cluster --config kind.yaml`

Verify the cluster is up and running:
```
$ kubectl get pods -A
NAMESPACE        	NAME                                     	READY   STATUS	RESTARTS   AGE
kube-system      	coredns-668d6bf9bc-6j97q                 	1/1 	Running   0      	2m44s
kube-system      	coredns-668d6bf9bc-nsvsb                 	1/1 	Running   0      	2m44s
kube-system      	etcd-kind-control-plane                  	1/1 	Running   0      	2m49s
kube-system      	kindnet-gkxd2                            	1/1 	Running   0      	2m44s
kube-system      	kube-apiserver-kind-control-plane        	1/1 	Running   0      	2m49s
kube-system      	kube-controller-manager-kind-control-plane   1/1 	Running   0      	2m49s
kube-system      	kube-proxy-94gkd                         	1/1 	Running   0      	2m44s
kube-system      	kube-scheduler-kind-control-plane        	1/1 	Running   0      	2m49s
local-path-storage   local-path-provisioner-7dc846544d-7mzbq  	1/1 	Running   0      	2m44s
```

Deploy Flight Control on Kind with

```
$ helm upgrade --install --version=0.7.1 \
	--namespace flightctl --create-namespace \
	flightctl oci://quay.io/flightctl/charts/flightctl \
	--set global.baseDomain=<YOUR-SYSTEM-A-IP ADDRESS>.nip.io \
	--set global.exposeServicesMethod=nodePort
```
Make sure Flight Control platform is running:
```
$ kubectl get pods -n flightctl
NAME                              	READY   STATUS  	RESTARTS    	AGE
flightctl-api-85945b9d9f-hldm5    	1/1 	Running 	1 (2m46s ago)   6m18s
flightctl-db-5c68587f4d-6z4tw     	1/1 	Running 	0           	6m18s
flightctl-kv-0                    	1/1 	Running 	0           	6m18s
flightctl-periodic-8595f8db48-d8kh8   1/1 	Running 	0           	6m18s
flightctl-secrets-bkrjj           	0/1 	Completed   0           	6m18s
flightctl-ui-867568898-fkktq      	1/1 	Running 	2 (36s ago) 	6m18s
flightctl-worker-64cb8947b8-tn7kv 	1/1 	Running 	1 (37s ago) 	6m18s
keycloak-74f56c76fd-665s8         	1/1 	Running 	4 (2m9s ago)	6m18s
keycloak-db-0                     	1/1 	Running 	0           	6m18s
```
In case the flight-ui pod is crashing delete it with

`$ kubectl delete pod -n flightctl flight-ui-.....`

You should now be able to open the relevant web page for Flight Control (after opening the dedicated firewall port on system A).
```
$ sudo firewall-cmd --zone=public --add-port=9000/tcp --permanent
success
$ sudo firewall-cmd --zone=public --add-port=3443/tcp --permanent
success
$ sudo firewall-cmd --zone=public --add-port=7443/tcp --permanent
success
$ sudo firewall-cmd --zone=public --add-port=8081/tcp --permanent
success
$ sudo firewall-cmd –reload
```
Navigate to http://<YOUR-SYSTEM-A-IP-ADDRESS>.nip.io:9000

Once you open the page you will get redirected to the authentication page (as Flight Control comes with a preconfigured IDP [https://www.keycloak.org/]).

You can get the password for the default user demouser like this:

`$ 	kubectl get secret -n flightctl keycloak-demouser-secret -o=jsonpath='{.data.password}' | base64 -d`



Make sure have KVM installed on the system with (in the case of Fedora):

```
$ sudo dnf group install --with-optional virtualization
$ sudo systemctl enable --now libvirtd
```

## Build v1 image

## Build v2 image (and automatic update with FlightCTL)