FROM docker.io/library/debian:trixie-slim AS base

RUN apt-get update \
	&& apt-get install -y --no-install-recommends gromacs curl ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lysozyme-water
COPY run.sh *.mdp ./

FROM base AS discovery
RUN apt-get update \
	&& apt-get install -y --no-install-recommends python3 \
	&& rm -rf /var/lib/apt/lists/* \
	&& mkdir -p /app/workdir /input /output
WORKDIR /app/workdir
CMD ["/bin/bash"]

FROM base AS cpu
ENTRYPOINT ["bash", "/opt/lysozyme-water/run.sh"]