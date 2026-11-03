# SPDX-License-Identifier: Apache-2.0
# Development/test oracles only; never part of the shipped Swift package.
FROM swift@sha256:bca121f6eb59fd80340d1296887b2698ed8f3eb9eca7d80c181f8af769dc7ee0
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++=4:13.2.0-7ubuntu1 \
    libcharls-dev=2.4.2-2build2 \
    libjxl-tools=0.7.0-10.2ubuntu6.1 \
    && rm -rf /var/lib/apt/lists/*
