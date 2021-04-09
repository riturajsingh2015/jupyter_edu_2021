FROM ubuntu:20.10

ARG NB_USER="student"
ARG NB_UID="1000"
ARG NB_GID="100"

USER root

ENV JAVA_HOME=/usr

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get --fix-missing update && apt-get -yq dist-upgrade && \
    apt-get install -yq --no-install-recommends \
    locales \
    wget \
    ca-certificates \
    openjdk-15-jdk-headless \
    mysql-server \
    git \
    nodejs \
    npm \
    graphviz \
    texlive-xetex \
    texlive-latex-recommended \
    texlive-latex-extra \
    texlive-fonts-recommended \
    r-base \
    r-recommended \
    fonts-liberation \
    unzip \
    fonts-freefont-ttf \
    fonts-freefont-otf \
    build-essential \
    gnuplot \
    ghostscript \
    octave \
    liboctave-dev \
    libgdcm3.0 \
    libgdcm-dev \
    cmake && \
    apt-get clean

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER

ADD fix-permissions /usr/local/bin/fix-permissions
RUN chmod +x /usr/local/bin/fix-permissions

# Create NB_USER user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN groupadd wheel -g 11 && \
    echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /opt

# Install conda as NB_USER and check the md5 sum provided on the download site
ENV MINICONDA_VERSION 4.9.2
RUN cd /tmp && \
    wget https://repo.continuum.io/miniconda/Miniconda3-py38_${MINICONDA_VERSION}-Linux-x86_64.sh && \
    echo "122c8c9beb51e124ab32a0fa6426c656 *Miniconda3-py38_${MINICONDA_VERSION}-Linux-x86_64.sh" | md5sum -c - && \
    /bin/bash Miniconda3-py38_${MINICONDA_VERSION}-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm Miniconda3-py38_${MINICONDA_VERSION}-Linux-x86_64.sh && \
    $CONDA_DIR/bin/conda config --system --prepend channels conda-forge && \
    $CONDA_DIR/bin/conda config --system --set auto_update_conda false && \
    $CONDA_DIR/bin/conda config --system --set show_channel_urls true && \
    $CONDA_DIR/bin/conda install --quiet --yes conda="${MINICONDA_VERSION%.*}.*" && \
    $CONDA_DIR/bin/conda update --all --quiet --yes && \
    conda clean -tipsy && \
    rm -rf $HOME/.cache/yarn && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR

# Install Jupyter Notebook, Lab, and Hub
# Generate a notebook server config
# Cleanup temporary files
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
RUN conda install --quiet --yes \
   'notebook' \
   'jupyterlab' &&  \
   conda clean -tipsy && \
   npm cache clean --force && \
   jupyter notebook --generate-config && \
   rm -rf $CONDA_DIR/share/jupyter/lab/staging && \
   rm -rf $HOME/.cache/yarn && \
   fix-permissions $HOME && \
   fix-permissions $CONDA_DIR

RUN octave --eval "pkg install -forge dicom" && \
    octave --eval "pkg install -forge image" && \
    conda install octave_kernel -c conda-forge

# Download and extract IJava kernel from SpencerPark
RUN cd /tmp && \
    wget https://github.com/SpencerPark/IJava/releases/download/v1.3.0/ijava-1.3.0.zip && \
    unzip ijava-1.3.0.zip && \
    python install.py --sys-prefix && \
    rm -rf /tmp/ijava*

# kernels, postgres and tools
RUN conda install -c r r-irkernel && \
    conda install xeus-cling -c conda-forge && \
    conda install rise -c conda-forge && \
    pip install pip --upgrade && \
    pip install sos sos-notebook sos-python sos-matlab sos-javascript sos-bash --upgrade && \
    python -m sos_notebook.install && \
    pip install nbformat --upgrade && \
    pip install nbconvert --upgrade && \
    pip install nbtoolbelt && \
    conda install -c conda-forge pydicom && \
    conda install -c jetbrains kotlin-jupyter-kernel && \
    conda install -y -c conda-forge ipython-sql && \
    conda install -y -c conda-forge postgresql && \
    conda install -y -c anaconda psycopg2 && \
    conda install -y -c conda-forge pgspecial && \
    conda install -c conda-forge jupyter_contrib_nbextensions && \
    conda install -c conda-forge jupyterlab_execute_time  && \
    pip install postgres_kernel && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR

RUN jupyter nbextension enable execute_time/ExecuteTime && \
    jupyter nbextension enable rubberband/main && \
    jupyter nbextension enable exercise2/main && \
    jupyter nbextension enable freeze/main && \
    jupyter nbextension enable hide_input/main && \
    jupyter nbextension enable init_cell/main && \
    jupyter nbextension enable scratchpad/main && \
    jupyter nbextension enable init_cell/main && \
    jupyter nbextension enable scroll_down/main && \
    jupyter nbextension enable toc2/main && \
    jupyter nbextension enable collapsible_headings/main && \
    jupyter labextension install transient-display-data && \
    jupyter labextension install jupyterlab-sos && \
    jupyter labextension install jupyterlab-drawio && \
    jupyter labextension install jupyterlab_iframe && \
    pip install ipycanvas && \
    jupyter labextension install ipycanvas

ADD my.cnf /etc/mysql/my.cnf
RUN chown $NB_USER:$NB_UID /etc/mysql/my.cnf && \
    mkdir -p /var/run/mysqld && \
    mkdir -p /usr/local/mysql/var && \
    chown -R $NB_USER:$NB_UID /var/lib/mysql && \
    chown -R $NB_USER:$NB_UID /var/log/mysql && \
    chown -R $NB_USER:$NB_UID /var/run/mysqld && \
    chown -R $NB_USER:$NB_UID /usr/local/mysql

# required in order to make mysqld work in docker container
VOLUME /usr/local/mysql/var

#fix problem cannot connect to kernel with container running on windows
#see https://github.com/jupyter/notebook/issues/2664
#RUN pip uninstall -y tornado && \
#    pip install tornado==5.1.1

# update tornado, so that build all remaining jupyter extensions works
RUN pip install tornado --upgrade && \
    jupyter lab build

# Install Tini
RUN conda install --quiet --yes 'tini=0.18.0' && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned && \
    conda clean -tipsy && \
    fix-permissions $CONDA_DIR && \
    fix-permissions $HOME

# add files
ADD --chown=$NB_USER:$NB_GID mysql_config.json $HOME/.local/config/mysql_config.json
ADD imshow.m /usr/share/octave/5.2.0/m/image/
ADD jupyter_notebook_config.py /etc/jupyter/
ADD start.sh /usr/local/bin/
ADD start-notebook.sh /usr/local/bin/
ADD --chown=$NB_USER:$NB_GID mysql-init $HOME/mysql/
ADD --chown=$NB_USER:$NB_GID start_mysql.sh $HOME/mysql/
ADD --chown=$NB_USER:$NB_GID start_postgresql.sh $HOME/postgresql/
ADD convert_to_html.sh /usr/local/bin/
ADD --chown=$NB_USER:$NB_GID tracker.jupyterlab-settings $HOME/.jupyter/lab/user-settings/@jupyterlab/notebook-extension/

# add example files
ADD --chown=$NB_USER:$NB_GID MySQLWithJavaDemo.ipynb $HOME/examples/
ADD --chown=$NB_USER:$NB_GID PostgreSQLWithJava.ipynb $HOME/examples/

RUN chmod +r /usr/share/octave/5.2.0/m/image/imshow.m && \
    fix-permissions /etc/jupyter/ && \
    chmod +rx /usr/local/bin/start.sh && \
    chmod +rx /usr/local/bin/start-notebook.sh && \
    chmod +x $HOME/mysql/start_mysql.sh && \
    chmod +x $HOME/postgresql/start_postgresql.sh && \
    chmod +rx /usr/local/bin/convert_to_html.sh

# MySQL kernel, pandas required for mysql kernel
RUN pip install git+https://github.com/shemic/jupyter-mysql-kernel --user && \
    pip install pandas && \
    pip install bash_kernel && \
    python -m bash_kernel.install && \
    fix-permissions $CONDA_DIR && \
    fix-permissions $HOME

WORKDIR $HOME

COPY entrypoint.sh /usr/local/bin/
RUN chmod +rx /usr/local/bin/entrypoint.sh

USER $NB_UID

EXPOSE 3306
EXPOSE 5432
EXPOSE 8888

RUN mkdir $HOME/workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/start-notebook.sh"]
