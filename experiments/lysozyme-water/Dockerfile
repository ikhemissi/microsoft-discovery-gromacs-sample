FROM docker.io/library/debian:trixie-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends gromacs curl ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lysozyme-water
COPY run.sh *.mdp ./
ENTRYPOINT ["bash", "/opt/lysozyme-water/run.sh"]