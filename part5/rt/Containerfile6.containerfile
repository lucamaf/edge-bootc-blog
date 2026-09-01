# Adding gnuplot & updating flightctl agent
# This image will be tagged as quay.io/luferrar/part5:device006rt
FROM quay.io/luferrar/part5:device003rt

# upgrade and install gnuplot
RUN dnf -y upgrade  && \
    dnf -y install gnuplot && \
    dnf clean all

# adding greenboot packages
RUN dnf -y install greenboot greenboot-default-health-checks && \
    dnf clean all

# Lint the build
RUN bootc container lint