FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies and GCC 4.8
RUN apt-get update && apt-get install -y \
    python2.7 python2.7-dev python-pip \
    wget git build-essential cmake \
    gcc-4.8 g++-4.8 libxml2-dev libcurl4-openssl-dev \
    nano ffmpeg

# Force the system to use GCC 4.8 as the default
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 100

# Force the symbolic link for Python 2.7
RUN ln -sf /usr/bin/python2.7 /usr/bin/python

# Install Python requirements
RUN pip install --upgrade pip && pip install bitstring

# Set Work Directory to the project root
WORKDIR /DASH-SVC-Toolchain

# Copy your Toolchain Source Code into the container
COPY . /DASH-SVC-Toolchain

# Configure environment paths
ENV JSVM_HOME=/DASH-SVC-Toolchain/jsvm
ENV PATH="/DASH-SVC-Toolchain/jsvm/bin:${PATH}"
ENV PATH="/DASH-SVC-Toolchain/build_scripts:${PATH}"
ENV LD_LIBRARY_PATH="/DASH-SVC-Toolchain/libdash/libdash/build:/usr/local/lib"

CMD ["/bin/bash"]