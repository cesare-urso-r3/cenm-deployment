#!/bin/sh

{{ if eq .Values.bashDebug true }}
set -x
{{ end }}

cat << EOF
===================================================================================
Network Migration Step:
-----------------------
The Kubernetes deployment has paused to allow you to perform manual migration steps

To continue with the deployment the init-token container requires the 
network-parameters-initial.conf file. This file should contain the network 
parameters to be used for the network. Make sure that the notary defined in the
network parameters is the OLD network notary node info file and NOT the new one.

Make sure that the relative path is set correctly in the network parameters file.
this should be

    '{{ .Values.nmapJar.configPath }}/<notary-node-info-file>'

The network paramters notary section should follow the template defined below:

### network-parameters-init.conf ##################################################
...

notaries : [
  {
    notaryNodeInfoFile: "{{ .Values.nmapJar.configPath }}/<notary-node-info-file>"
    validating = false
  }
]

...
###################################################################################

1. Upload the 'network-parameters-initial.conf' file to the notary-nodeinfo directory
    kubectl cp -c init-token network-parameters-initial.conf cenm/$(hostname):/opt/cenm/notary-nodeinfo/network-parameters-initial.conf

Once the 'network-parameters-initial.conf' file has been uploaded, this script will
carry on with the deployment and create a subzone token using these network parameters.
===================================================================================
Waiting for /opt/cenm/notary-nodeinfo/network-parameters-initial.conf
===================================================================================
EOF

until [ -f notary-nodeinfo/network-parameters-initial.conf ]
do
    sleep 10
done
echo "Waiting for notary-nodeinfo/network-parameters-initial.conf ... done."

ls -al notary-nodeinfo/network-parameters-initial.conf
cp notary-nodeinfo/network-parameters-initial.conf {{ .Values.nmapJar.configPath }}/
cat {{ .Values.nmapJar.configPath }}/network-parameters-initial.conf

cat {{ .Values.nmapJar.configPath }}/networkmap-init.conf

if [ ! -f {{ .Values.nmapJar.configPath }}/token ]
then
    EXIT_CODE=1
    until [ "${EXIT_CODE}" -eq "0" ]
    do
        echo "Trying to login to {{ .Values.prefix }}-gateway:8080 ..."
        java -jar bin/cenm-tool.jar context login -s http://{{ .Values.prefix }}-gateway:8080 -u network-maintainer -p p4ssWord
        EXIT_CODE=${?}
        if [ "${EXIT_CODE}" -ne "0" ]
        then
            echo "EXIT_CODE=${EXIT_CODE}"
            sleep 5
        else
            break
        fi
    done
    cat ./notary-nodeinfo/network-parameters-initial.conf
    ZONE_TOKEN=$(java -jar bin/cenm-tool.jar zone create-subzone \
        --config-file={{ .Values.nmapJar.configPath }}/networkmap-init.conf --network-map-address={{ .Values.prefix }}-nmap-internal:{{ .Values.adminListener.port }} \
        --network-parameters=./notary-nodeinfo/network-parameters-initial.conf --label=Main --label-color='#941213' --zone-token)
    echo ${ZONE_TOKEN}
    echo ${ZONE_TOKEN} > {{ .Values.nmapJar.configPath }}/token
    {{ if eq .Values.bashDebug true }}
    cat {{ .Values.nmapJar.configPath }}/token
    {{ end }}
fi
