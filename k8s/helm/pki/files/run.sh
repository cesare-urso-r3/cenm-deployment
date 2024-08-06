#!/bin/sh
{{ if eq .Values.bashDebug true }}
set -x
{{ end }}

#
# main run
#
echo "Waiting for /opt/cenm/HSM/HSM-LOAD-DONE ..."
until [ -f /opt/cenm/HSM/HSM-LOAD-DONE ]
do
  sleep 2
done

if [ -f {{ .Values.pkiJar.path }}/pkitool.jar ]
then
{{ if eq .Values.bashDebug true }}
    sha256sum {{ .Values.pkiJar.path }}/pkitool.jar
{{ if eq .Values.bashDebug true }}
    cat {{ .Values.pkiJar.configPath }}/{{ .Values.pkiJar.configFile }}
{{ end }}
{{ end }}
    echo
    echo "CENM: starting PKI Tool process ..."
    echo
    echo "time java -Xmx{{ .Values.pkiJar.xmx }} -jar {{ .Values.pkiJar.path }}/pkitool.jar --config-file {{ .Values.pkiJar.configPath }}/{{ .Values.pkiJar.configFile }}"
    time java -Xmx{{ .Values.pkiJar.xmx }} -jar {{ .Values.pkiJar.path }}/pkitool.jar --config-file {{ .Values.pkiJar.configPath }}/{{ .Values.pkiJar.configFile }}
    EXIT_CODE=${?}
else
    echo "Missing PKI Tool jar file in {{ .Values.pkiJar.path }} directory:"
    ls -al {{ .Values.pkiJar.path }}
    EXIT_CODE=110
fi

if [ "${EXIT_CODE}" -ne "0" ]
then
    HOW_LONG={{ .Values.sleepTimeAfterError }}
    echo
    echo "PKI Tool failed - exit code: ${EXIT_CODE} (error)"
    echo
    echo "Going to sleep for requested ${HOW_LONG} seconds to let you login and investigate."
    echo
else
    # Network migration steps #
    # -------------------------------------------------------------------------------------------------------- #
cat << EOF
===================================================================================
Network Migration Step:
-----------------------
The Kubernetes deployment has paused to allow you to perform manual migration steps

1. Download the 'network-root-truststore.jks' file from the container

    kubectl cp -c main cenm/$(hostname):/opt/cenm/DATA/trust-stores/network-root-truststore.jks ./network-root-truststore.jks

2. Run the Corda HA-utilities JAR to merge the new 'network-root-truststore.jks' file with 
   the Corda Network 'network-root-truststore.jks' file

    java -jar corda-tools-ha-utilities.jar merge-network-trustroots \\
        --old-network-root-truststore old_network-root-truststore.jks \\
        --old-network-root-truststore-password <old-password> \\
        --new-network-root-truststore ./network-root-truststore.jks \\
        --new-network-root-truststore-password <new-password> \\
        --old-corda-root-ca-alias cordarootca

3. Upload the 'merged_network-root-truststore.jks' file back to the container
   this script is waiting for a file named 'merged_network-root-truststore.jks'
   in '/opt/cenm/DATA/trust-stores'

   kubectl cp -c main output/merged_network-root-truststore.jks cenm/$(hostname):/opt/cenm/DATA/trust-stores/merged_network-root-truststore.jks

Currently the SHA256 checksum for the 'network-root-truststore.jks' file is: 

    $(sha256sum ./DATA/trust-stores/network-root-truststore.jks)

Once the new 'merged_network-root-truststore.jks' file has been uploaded, this 
script will automatically rename the following files in '/opt/cenm/DATA/trust-stores'
    - 'network-root-truststore.jks' -> 'new_network-root-truststore.jks'
    - 'merged_network-root-truststore.jks' -> 'network-root-truststore.jks'

and new checksums will be displayed.
===================================================================================
Waiting for /opt/cenm/DATA/trust-stores/merged_network-root-truststore.jks
===================================================================================
EOF
    until [ -f ./DATA/trust-stores/merged_network-root-truststore.jks ]
    do
        sleep 2
    done
    echo "updating network-root-truststore files"
    sha256sum ./DATA/trust-stores/network-root-truststore.jks
    mv ./DATA/trust-stores/network-root-truststore.jks ./DATA/trust-stores/new_network-root-truststore.jks
    sha256sum ./DATA/trust-stores/new_network-root-truststore.jks
    sha256sum ./DATA/trust-stores/merged_network-root-truststore.jks
    mv ./DATA/trust-stores/merged_network-root-truststore.jks ./DATA/trust-stores/network-root-truststore.jks
    sha256sum ./DATA/trust-stores/network-root-truststore.jks
    # -------------------------------------------------------------------------------------------------------- #
    touch ./DATA/PKITOOL-DONE
    ls -al ./DATA/
    HOW_LONG=0
fi

sleep ${HOW_LONG}
echo