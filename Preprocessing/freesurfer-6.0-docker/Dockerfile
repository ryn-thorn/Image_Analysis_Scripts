FROM ubuntu:16.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FREESURFER_HOME=/opt/freesurfer
ENV SUBJECTS_DIR=/subjects

RUN apt-get update && apt-get install -y \
    bc \
    binutils \
    libgomp1 \
    libxmu6 \
    libxt6 \
    perl \
    tcsh \
    wget \
    unzip \
    xorg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN wget -q https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/6.0.0/freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz && \
    tar -xzf freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz && \
    rm freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz

COPY license.txt /opt/freesurfer/.license

RUN echo "source /opt/freesurfer/SetUpFreeSurfer.sh" >> /etc/bash.bashrc

ENV PATH=$FREESURFER_HOME/bin:$PATH

CMD ["bash"]

