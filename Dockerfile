ARG AIRFLOW_VERSION="2.5.0-python3.10"

FROM apache/airflow:${AIRFLOW_VERSION}
MAINTAINER  Kumar Bipulesh

ENV AIRFLOW_VERSION=2.5.0
ENV AIRFLOW_PYTHON_VERSION=3.10

# Config and Constraint file
ENV AIRFLOW_CONFIG_FILE="./airflow/config/airflow-${AIRFLOW_VERSION}-${AIRFLOW_PYTHON_VERSION}.cfg"
ENV AIRFLOW_CONSTRAINTS_FILE="./airflow/constraints/constraints-${AIRFLOW_VERSION}-${AIRFLOW_PYTHON_VERSION}.txt"

# Patch to disable Swagger UI
COPY    ./airflow/src/www/extensions/init_views.py /home/airflow/.local/lib/python${AIRFLOW_PYTHON_VERSION}/site-packages/airflow/www/extensions/
COPY    ./airflow/src/www/extensions/init_appbuilder_links.py /home/airflow/.local/lib/python${AIRFLOW_PYTHON_VERSION}/site-packages/airflow/www/extensions/

# Airflow
ARG AIRFLOW_USER_HOME=/opt/airflow
ENV AIRFLOW_HOME=${AIRFLOW_USER_HOME}

USER        root
RUN         apt-get update

# CVE-2021-29921 Fix (wiz)
RUN         apt-get autoremove -y python3.9

RUN         apt-get --only-upgrade install -y libcurl4
RUN         apt-get --only-upgrade install -y zlib1g

# CVE-2022-40303
RUN         apt-get --only-upgrade install -y libxml2

# vim
RUN         apt-get install -y vim

# Installing Oracle instant client
WORKDIR     /opt/oracle
RUN         apt-get install -y g++
RUN         apt-get install -y libaio1 wget unzip \
            && wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-basiclite-linuxx64.zip \
            && unzip instantclient-basiclite-linuxx64.zip \
            && rm -f instantclient-basiclite-linuxx64.zip \
            && cd /opt/oracle/instantclient* \
            && rm -f *jdbc* *occi* *mysql* *README *jar uidrvci genezi adrci \
            && echo /opt/oracle/instantclient* > /etc/ld.so.conf.d/oracle-instantclient.conf \
            && ldconfig

COPY    ./airflow/files/tnsnames.ora /opt/oracle/instantclient_21_1/network/admin/

ENV     ORACLE_HOME=/opt/oracle/instantclient_21_1
ENV     PATH=$PATH:$ORACLE_HOME/bin
ENV     LD_LIBRARY_PATH=$ORACLE_HOME/lib
ENV     TNS_ADMIN=$ORACLE_HOME/network/admin

RUN     curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN     unzip awscliv2.zip
RUN     ./aws/install


COPY    ${AIRFLOW_CONFIG_FILE} ${AIRFLOW_HOME}/airflow.cfg
COPY    ./entrypoint.sh ${AIRFLOW_HOME}/entrypoint.sh
COPY    ./airflow/config/.env ${AIRFLOW_HOME}/.env
COPY    ./airflow/config/webserver_config.py ${AIRFLOW_HOME}/webserver_config.py


RUN     chmod +x ${AIRFLOW_HOME}/entrypoint.sh
RUN     chown -R airflow: ${AIRFLOW_HOME}

EXPOSE  8080 5555 8793 8888

#RUN     echo "airflow:airflow" | chpasswd && adduser airflow sudo
USER    airflow

# By copying over requirements first, we make sure that Docker will cache
# our installed requirements rather than reinstall them on every build
# Constraint file path is mentioned here: https://airflow.apache.org/docs/apache-airflow/stable/installation/installing-from-pypi.html
# Check version conflict using: pip install --dry-run -c ./airflow/constraints/constraints-2.5.0-3.10.txt -r requirements.txt
COPY    ${AIRFLOW_CONSTRAINTS_FILE} /app/constraints.txt
COPY    requirements.txt /app/requirements.txt

RUN     python -m pip install --upgrade pip

COPY    ./airflow/pkg/de_pytools-0.0.4-py3-none-any.whl /opt/airflow/pkg/
COPY    ./airflow/pkg/de_qualtrics-0.0.1-py3-none-any.whl /opt/airflow/pkg/
RUN     pip install /opt/airflow/pkg/de_pytools-0.0.4-py3-none-any.whl --force-reinstall --constraint /app/constraints.txt
RUN     pip install /opt/airflow/pkg/de_qualtrics-0.0.1-py3-none-any.whl --force-reinstall --constraint /app/constraints.txt

RUN     pip install --user -r /app/requirements.txt --constraint /app/constraints.txt

WORKDIR     ${AIRFLOW_HOME}
ENTRYPOINT ["./entrypoint.sh"]
