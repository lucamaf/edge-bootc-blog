# This image will be tagged as quay.io/luferrar/part5:device002rt
FROM quay.io/luferrar/part5:device001rt

# enable tailscale port 
RUN firewall-offline-cmd --add-port=41641/udp

# adding and configuring Tailscale for VPN access
RUN dnf config-manager -y --add-repo https://pkgs.tailscale.com/stable/rhel/9/tailscale.repo && \
    dnf -y install tailscale && \
    dnf -y clean all
RUN systemctl enable tailscaled

# set automatic Taiscale login using script at boot time
COPY tailscale-login.service /etc/systemd/system/tailscale-login.service
RUN systemctl enable tailscale-login.service && touch /etc/.run_tailscale_next_boot

# Update hardcoded host file for demo purposes
COPY hosts /etc/hosts

# Lint the build
RUN bootc container lint