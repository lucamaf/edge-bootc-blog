# Adding gnuplot & updating flightctl agent
# adding tailscale for VPN access
# adding beszel binary
# This image will be tagged as quay.io/luferrar/part5:device008rt
FROM quay.io/luferrar/part5:device007rt

# upgrade and install gnuplot
# --exclude on the plain kernel packages stops a bare "dnf upgrade" from
# silently pulling the standard kernel back in alongside kernel-rt (nothing
# at the RPM level prevents them being co-installed); kernel-rt-* itself is
# still upgraded normally. The find/rm mirrors the cleanup in Containerfile7
# as a second line of defense in case something still slips a non-rt kernel
# directory in.
RUN dnf -y upgrade --exclude=kernel --exclude=kernel-core --exclude=kernel-modules --exclude=kernel-modules-extra  --exclude=kernel-modules-core && \
    dnf -y install gnuplot && \
    dnf clean all && \
    find /usr/lib/modules/ -mindepth 1 -maxdepth 1 -type d ! -iname '*rt*' -exec rm -rf {} +

# adding greenboot packages
RUN dnf -y install greenboot greenboot-default-health-checks && \
    dnf clean all

# enable tailscale port 
RUN firewall-offline-cmd --add-port=41641/udp

# adding and configuring Tailscale for VPN access
RUN dnf config-manager -y --add-repo https://pkgs.tailscale.com/stable/rhel/10/tailscale.repo && \
    dnf -y install tailscale && \
    dnf -y clean all
RUN systemctl enable tailscaled

# beszel binary installation
RUN curl -sL "https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_$(uname -s)_$(uname -m | sed -e 's/x86_64/amd64/' -e 's/armv6l/arm/' -e 's/armv7l/arm/' -e 's/aarch64/arm64/').tar.gz" | tar -xz beszel-agent && mv beszel-agent /usr/local/bin/beszel-agent && chmod +x /usr/local/bin/beszel-agent

# disable serial port console
RUN systemctl disable serial-getty@ttyS1.service

# Lint the build
RUN bootc container lint