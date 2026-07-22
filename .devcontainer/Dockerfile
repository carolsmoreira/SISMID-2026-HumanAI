FROM ghcr.io/rocker-org/devcontainer/tidyverse:4

# Course R packages. install.R is the ONE place to edit the package list.
COPY .devcontainer/install.R /tmp/install.R
RUN Rscript /tmp/install.R && rm /tmp/install.R
