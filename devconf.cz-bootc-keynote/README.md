# Running the second demo at devconf.cz keynote 2025

Install kind and kubectl cli tools.

Deploy kind on a system in rootless mode with:

`$ systemd-run --scope --user -p "Delegate=yes" kind create cluster --config kind.yaml`

Deploy Flight Control on Kind with

``

Make sure have KVM installed on the system with (in the case of Fedora):

```
$ sudo dnf group install --with-optional virtualization
$ sudo systemctl enable --now libvirtd
```

## Build v1 image

## Build v2 image (and automatic update with FlightCTL)