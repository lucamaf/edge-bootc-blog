# Update to flightctl agent 1.1.2
# This image will be tagged as quay.io/luferrar/part5:device003rt
FROM quay.io/luferrar/part5:device002rt

RUN dnf -y upgrade && \
    dnf clean all

# Lint the build
RUN bootc container lint