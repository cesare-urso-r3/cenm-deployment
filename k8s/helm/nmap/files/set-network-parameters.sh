#!/bin/sh
{{ if eq .Values.bashDebug true }}
set -x
{{ end }}

# Network migration steps #
# -------------------------------------------------------------------------------------------------------- #
echo "Waiting for notary nodeinfo file"
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
cp notary-nodeinfo/nodeInfo* {{ .Values.nmapJar.configPath }}/
sha256sum {{ .Values.nmapJar.configPath }}/nodeInfo*
# -------------------------------------------------------------------------------------------------------- #
echo "Waiting for notary-nodeinfo/network-parameters-initial.conf ..."
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
