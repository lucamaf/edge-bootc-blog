FROM quay.io/centos-bootc/centos-bootc:stream9

RUN dnf -y copr enable @redhat-et/flightctl epel-9-x86_64 && \
    dnf -y group install GNOME && \
    dnf -y install flightctl-agent mkpasswd firefox && \
    dnf -y clean all && \
    systemctl set-default graphical.target && \
    systemctl enable flightctl-agent.service

RUN pass=$(mkpasswd --method=SHA-512 --rounds=4096 redhat) && useradd -m -G wheel kiosk-user && \
    echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo && \
    mkdir -p /home/kiosk-user/.config/autostart

COPY ./tailwind.container /usr/share/containers/systemd/tailwind.container
RUN ln -s /usr/share/containers/systemd/tailwind.container /usr/lib/bootc/bound-images.d/tailwind.container

ADD firefox.desktop /home/kiosk-user/.config/autostart/
ADD config.yaml /etc/flightctl/
RUN chown -R kiosk-user:kiosk-user /home/kiosk-user/.config
