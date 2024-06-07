#!/bin/bash

# Start the timer
start_time=$(date +%s)

# Get APEX
curl -o apex-latest.zip https://download.oracle.com/otn_software/apex/apex-latest.zip

# Enter APEX Folder
unzip -q apex-latest.zip
rm apex-latest.zip
cd apex

# Install APEX
sqlplus / as sysdba <<EOF
ALTER SESSION SET CONTAINER = FREEPDB1;
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF

# Set Accounts
sqlplus / as sysdba <<EOF
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY E;
EXIT;
EOF

# Create ADMIN Account silently
sqlplus / as sysdba <<EOF
ALTER SESSION SET CONTAINER = FREEPDB1;
BEGIN
    APEX_UTIL.set_security_group_id( 10 );
    
    APEX_UTIL.create_user(
        p_user_name       => 'ADMIN',
        p_email_address   => 'me@example.com',
        p_web_password    => 'OrclAPEX1999!',
        p_developer_privs => 'ADMIN' );
        
    APEX_UTIL.set_security_group_id( null );
    COMMIT;
END;
/
EOF

# Start of ORDS
mkdir /home/oracle/software
mkdir /home/oracle/software/apex
mkdir /home/oracle/software/ords
mkdir /home/oracle/scripts

# Copy APEX images
cp -r /home/oracle/apex/images /home/oracle/software/apex
cd /home/oracle/

# Install software
su - <<EOF
cat /dev/null > /etc/dnf/vars/ociregion
dnf update -y
dnf install sudo -y
dnf install nano -y
dnf install java-17-openjdk -y
EOF

# Modify sudoers
su - <<EOF
echo "Defaults !lecture" | sudo tee -a /etc/sudoers
echo "oracle ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers
EOF

# Make ORDS Folders
su - <<EOF
mkdir /etc/ords
mkdir /etc/ords/config
mkdir /home/oracle/logs
chmod -R 777 /etc/ords
EOF

# Install ORDS
su - <<EOF
yum-config-manager --add-repo=http://yum.oracle.com/repo/OracleLinux/OL8/oracle/software/x86_64
dnf install ords -y
EOF

# Configure ORDS
su - <<EOF
export ORDS_CONFIG=/etc/ords/config
export DB_PORT=1521
export DB_SERVICE=FREEPDB1
export SYSDBA_USER=SYS

ords --config \${ORDS_CONFIG} install \
     --admin-user \${SYSDBA_USER} \
     --db-hostname \${HOSTNAME} \
     --db-port \${DB_PORT} \
     --db-servicename \${DB_SERVICE} \
     --feature-db-api true \
     --feature-rest-enabled-sql true \
     --feature-sdw true \
     --gateway-mode proxied \
     --gateway-user APEX_PUBLIC_USER \
     --password-stdin <<EOT
E
E
EOT
EOF

# Create a start ORDS
su - <<EOF
echo 'export ORDS_HOME=/usr/local/bin/ords' > /home/oracle/scripts/start_ords.sh
echo 'export _JAVA_OPTIONS="-Xms512M -Xmx512M"' >> /home/oracle/scripts/start_ords.sh
echo 'LOGFILE=/home/oracle/logs/ords-$(date +"%Y%m%d").log' >> /home/oracle/scripts/start_ords.sh
echo 'nohup \${ORDS_HOME} --config /etc/ords/config serve >> \$LOGFILE 2>&1 & echo "View log file with : tail -f \$LOGFILE"' >> /home/oracle/scripts/start_ords.sh
EOF


# Create a start ORDS
su - <<EOF
echo 'kill \`ps -ef | grep [o]rds.war | awk "{print \$2}"\`' > /home/oracle/scripts/stop_ords.sh
sed -i 's/"/'\''/g' /home/oracle/scripts/stop_ords.sh
EOF

# Create a startup script
su - <<EOF
echo 'sudo sh /home/oracle/scripts/start_ords.sh' > /opt/oracle/scripts/startup/01_auto_ords.sh
EOF

# Configure ORDS Standalone
su - <<EOF
ords --config /etc/ords/config config set standalone.context.path /ords 
ords --config /etc/ords/config config set standalone.doc.root /etc/ords/config/global/doc_root 
ords --config /etc/ords/config config set standalone.http.port 8080
ords --config /etc/ords/config config set standalone.static.context.path /i 
ords --config /etc/ords/config config set standalone.static.path /home/oracle/software/apex/images/ 
ords --config /etc/ords/config config set jdbc.InitialLimit 15 
ords --config /etc/ords/config config set jdbc.MaxLimit 25 
ords --config /etc/ords/config config set jdbc.MinLimit 15  
EOF

# Fix MBEAN Warning
file_path=$(find / -name "logging.properties" 2>/dev/null | head -n 1)
echo $file_path
# Check if file_path is not empty
if [ -n "$file_path" ]; then
    # Append the line to the file
    echo "oracle.jdbc.level=OFF" | sudo tee -a "$file_path"
else
    echo "Logging properties file not found."
fi

# Start ORDS
su - <<EOF
sh /home/oracle/scripts/start_ords.sh
EOF

# Delete Startup file
su - <<EOF
rm /opt/oracle/scripts/startup/00_start_apex_ords_installer.sh
EOF

# Calculate the elapsed time
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

# Convert elapsed time to human-readable format (optional)
hours=$((elapsed_time / 3600))
minutes=$(( (elapsed_time % 3600) / 60 ))
seconds=$((elapsed_time % 60))

# Print the elapsed time
echo "Elapsed time: ${hours}h ${minutes}m ${seconds}s"


echo '### APEX INSTALLED ###'
                                                                 
