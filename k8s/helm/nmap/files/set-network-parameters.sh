#!/bin/sh
{{ if eq .Values.bashDebug true }}
set -x
{{ end }}

# Network migration steps #
# -------------------------------------------------------------------------------------------------------- #
cat << EOF
===================================================================================
Network Migration Step:
-----------------------
The Kubernetes deployment has paused to allow you to perform manual migration steps

To continue with the deployment the main container requires the OLD network notary
node info file. This file should be uploaded to the notary-nodeinfo directory.

1. Upload the 'nodeInfo-[node-info-hash]' file to the notary-nodeinfo directory

    kubectl cp -c main <notary-node-info-file> cenm/$(hostname):/opt/cenm/notary-nodeinfo/<notary-node-info-file>

Once the 'nodeInfo-[node-info-hash]' file has been uploaded, this script will 
automatically move the notary node info file from

    - 'notary-nodeinfo/' to '{{ .Values.nmapJar.configPath }}/'

and checksums will be displayed.
===================================================================================
Waiting for a file in /opt/cenm/notary-nodeinfo/
matching the pattern 'nodeInfo*'
===================================================================================
EOF
WAIT=true
while [[ $WAIT == true ]]
do
    for FILE in notary-nodeinfo/*; do
        if [[ "$FILE" == *"nodeInfo"* ]]; then
            WAIT=false
            break
        else
            sleep 10
        fi
    done
done
sha256sum notary-nodeinfo/nodeInfo*
echo "Copying notary node info files from notary-nodeinfo/ to {{ .Values.nmapJar.configPath }}/ ..."
cp notary-nodeinfo/nodeInfo* {{ .Values.nmapJar.configPath }}/
sha256sum {{ .Values.nmapJar.configPath }}/nodeInfo*
nodeInfoFile=$(ls {{ .Values.nmapJar.configPath }}/nodeInfo* | rev | cut -d'/' -f 1 | rev)
echo "Waiting for notary-nodeinfo/${nodeInfoFile} ... done."

cat << EOF
===================================================================================
Network Migration Step:
-----------------------
The Kubernetes deployment has paused to allow you to perform manual migration steps

To continue with the deployment the main container requires the 
'network-parameters-initial.conf' file. This file should contain the network 
parameters to be used for the network. Make sure that the notary defined in the
network parameters is the OLD network notary node info file and NOT the new one.

Make sure that the relative path is set correctly in the network parameters file.
this should be

    '{{ .Values.nmapJar.configPath }}/${nodeInfoFile}'

The network paramters notary section should follow the template defined below:

### network-parameters-init.conf ##################################################
...

notaries : [
  {
    notaryNodeInfoFile: "{{ .Values.nmapJar.configPath }}/${nodeInfoFile}"
    validating = false
  }
]

...
###################################################################################

1. Upload the 'network-parameters-initial.conf' file to the notary-nodeinfo directory

    kubectl cp -c main network-parameters-initial.conf cenm/$(hostname):/opt/cenm/notary-nodeinfo/network-parameters-initial.conf

Once the 'network-parameters-initial.conf' file has been uploaded, this script will
carry on with the deployment and set the network parameters using the:

    --ignore-notary-cert-checking-on-initial-set-network-parameters

command line flag.
===================================================================================
Waiting for /opt/cenm/notary-nodeinfo/network-parameters-initial.conf
===================================================================================
EOF
# -------------------------------------------------------------------------------------------------------- #
if [ ! -f {{ .Values.nmapJar.configPath }}/network-parameters-initial-set-skip-succesfully ]
then
    until [ -f notary-nodeinfo/network-parameters-initial.conf ]
    do
        sleep 1
    done
fi
echo "Waiting for notary-nodeinfo/network-parameters-initial.conf ... done."

ls -al notary-nodeinfo/network-parameters-initial.conf
cp notary-nodeinfo/network-parameters-initial.conf {{ .Values.nmapJar.configPath }}/
cat {{ .Values.nmapJar.configPath }}/network-parameters-initial.conf

cat {{ .Values.nmapJar.configPath }}/networkmap-init.conf

echo "Setting initial network parameters ..."
java -jar {{ .Values.nmapJar.path }}/networkmap.jar \
	-f {{ .Values.nmapJar.configPath }}/networkmap-init.conf \
	--set-network-parameters {{ .Values.nmapJar.configPath }}/network-parameters-initial.conf \
    --ignore-notary-cert-checking-on-initial-set-network-parameters \
	--network-truststore DATA/trust-stores/network-root-truststore.jks \
	--truststore-password trust-store-password \
	--root-alias cordarootca

EXIT_CODE=${?}

if [ "${EXIT_CODE}" -ne "0" ]
then
    echo
    echo "Network Map: setting network parameters failed - exit code: ${EXIT_CODE} (error)"
    echo
    echo "Going to sleep for the requested {{ .Values.sleepTimeAfterError }} seconds to let you log in and investigate."
    echo
    sleep {{ .Values.sleepTimeAfterError }}
else
    echo
    echo "Network Map: initial network parameters have been set."
    echo "No errors."
    echo
    touch {{ .Values.nmapJar.configPath }}/network-parameters-initial-set-skip-succesfully
    echo "# This is a file with _example_ content needed for updating network parameters" > {{ .Values.nmapJar.configPath }}/network-parameters-update-example.conf
    cat {{ .Values.nmapJar.configPath }}/network-parameters-initial.conf >> {{ .Values.nmapJar.configPath }}/network-parameters-update-example.conf
cat << EOF >> {{ .Values.nmapJar.configPath }}/network-parameters-update-example.conf
# updateDeadline=\$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ' -d "+10 minute")
parametersUpdate {
    description = "Update network parameters settings"
    updateDeadline = "[updateDeadline]"
}
EOF

fi

exit ${EXIT_CODE}
