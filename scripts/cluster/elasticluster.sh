source /scripts/cluster/cluster_install.sh

install_elasticluster(){
    elastic_dir="/opt/elasticluster"
    playbook_dir=$elastic_dir/src/elasticluster/share/playbooks
    hosts_dir=$playbook_dir
    
    if isubuntu; then
        apt-get update -y
        apt-get install -y gcc g++ git libc6-dev libffi-dev libssl-dev python-dev git
        curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
        python get-pip.py
    elif iscentos; then
        yum update -y
        yum install -y gcc gcc-c++ git libffi-devel openssl-devel python-devel git python-pip
    fi
    
    pip install --upgrade 'pip>=9.0.0'
    pip install --upgrade setuptools
    pip install backports.ssl_match_hostname
    
    mkdir $elastic_dir
    cd $elastic_dir
    git clone https://github.com/gc3-uzh-ch/elasticluster.git src
    cd src
    
    pip install -e .
    elasticluster list-templates 1>/dev/null 2>/dev/null
    echo "" > $playbook_dir/hosts
    
}

install_ansible(){
    #if isubuntu; then
    #    apt-get update -y
    #    apt-get install -y software-properties-common
    #    apt-add-repository -y ppa:ansible/ansible
    #    apt-get update -y
    #    apt-get install -y ansible
    #elif iscentos; then
    #    yum install -y epel-release
    #    yum install -y ansible
    #fi
    ORCH_IP=$(ss-get hostname)
    
    echo "[ansible]" >> $playbook_dir/hosts
    echo $ORCH_IP >> $playbook_dir/hosts
    
    if [ -f /root/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -f /root/.ssh/id_rsa -q -P ""
        cat /root/.ssh/id_rsa.pub | cat >> /root/.ssh/authorized_keys
    fi
    
    if [ -f /root/.ssh/config ]; then
        echo "Host $ORCH_IP #GEN_HOSTS_CONFIG" > /root/.ssh/config
        echo "   StrictHostKeyChecking no" >> /root/.ssh/config
        echo "   UserKnownHostsFile /dev/null" >> /root/.ssh/config
    fi
    
    ansible-playbook -M $playbook_dir/library -i $playbook_dir/hosts $playbook_dir/roles/ansible.yml
    
    #ansible_dir="/etc/ansible"
    #sed -i '/\[defaults\]/a library = /usr/share/ansible:library' $ansible_dir/ansible.cfg
    #sed -i 's|#host_key_checking.*|host_key_checking = False|' $ansible_dir/ansible.cfg
}

config_elasticluster(){
    
    #master
    msg_info "Waiting ip of master to be ready."
    MASTER_HOSTNAME=master
    ss-get --timeout=3600 $MASTER_HOSTNAME:ip.ready
    MASTER_IP=$(ss-get $MASTER_HOSTNAME:ip.ready)
    echo "[slurm_master]" >> $playbook_dir/hosts
    echo $MASTER_IP >> $playbook_dir/hosts
    
    #slave
    echo "" >> $playbook_dir/hosts
    echo "[slurm_worker]" >> $playbook_dir/hosts
    SLAVE_NAME=slave
    for (( i=1; i <= $(ss-get slave:multiplicity); i++ )); do
        msg_info "Waiting ip of slave to be ready."
        ss-get --timeout=3600 $SLAVE_NAME.$i:ip.ready
        SLAVE_IP=$(ss-get $SLAVE_NAME.$i:ip.ready)
        echo $SLAVE_IP >> $playbook_dir/hosts
    done
}

fix_elasticluster(){
    #FIX bug with conditional
    sed -i "s|'is_ubuntu_trusty'|'is_ubuntu_trusty\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nis/tasks/init-Debian.yml
    sed -i "s|'is_debian_compatible'|'is_debian_compatible\|default([])'|g" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nis/tasks/main.yml
    sed -i "s|'is_rhel_compatible'|'is_rhel_compatible\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nis/tasks/main.yml
    sed -i "s|'is_debian_compatible'|'is_debian_compatible\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nfs-server/tasks/init-Debian.yml
    sed -i "s|'is_debian_jessie'|'is_debian_jessie\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nfs-server/tasks/init-Debian.yml
    sed -i "s|is_debian_compatible|is_debian_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/init-Debian.yml
    sed -i "s|'is_rhel_compatible'|'is_rhel_compatible\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/main.yml
    sed -i "s|is_debian_compatible|is_debian_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/main.yml
    sed -i "s|is_rhel_compatible|is_rhel_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/main.yml
    sed -i "s|init_is_systemd|init_is_systemd\|default([])|g" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    sed -i "s|is_debian_compatible|is_debian_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    sed -i "s|is_rhel_compatible|is_rhel_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    sed -i "s|is_ubuntu_14_04|is_ubuntu_14_04\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    sed -i "s|is_ubuntu_14_10|is_ubuntu_14_10\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    mkdir -p /etc/munge
    useradd munge
    chown munge /etc/munge
    apt-get install -y munge
    echo 'OPTIONS="--force"' >> /etc/default/munge
    chown munge /var/log/munge/
}

install_slurm(){
    ansible-playbook -M $playbook_dir/library -i $playbook_dir/hosts $playbook_dir/roles/slurm.yml
}