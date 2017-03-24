#!/bin/bash

# usage example:
# ./migrate_backup.sh --orchestration_name=orchTest --instance_uuid=af1c7a70-35ee-4276-a595-665913f1f4dc --backup_date=201701261457 --old_tenant_name=old_tenant_test --new_tenant_name=new-tenant-test --old_vnet_name=eoib-vlan110 --new_vnet_name=eoib-vlan116

## arguments retrieval
for i in "$@"
do
        case $i in
                --orchestration_name=*)
                        ORCH="${i#*=}"
                        ;;
                --instance_uuid=*)
                        INSTUUID="${i#*=}"
                        ;;
                --backup_date=*)
                        BACKUPDATE="${i#*=}"
                        ;;
                --old_tenant_name=*)
                        OLDTENANT="${i#*=}"
                        ;;
                --new_tenant_name=*)
                        NEWTENANT="${i#*=}"
                        ;;
                --old_vnet_name=*)
                        OLDVNET="${i#*=}"
                        ;;
                --new_vnet_name=*)
                        NEWVNET="${i#*=}"
                        ;;
                *)
                        echo Error: Unknow argument
                        exit
                        ;;
        esac
done
if [[ ! $ORCH || ! $INSTUUID || ! $BACKUPDATE || ! $OLDTENANT || ! $NEWTENANT || ! $OLDVNET || ! $NEWVNET ]] ; then
        echo "Error: missing arguments"
        echo "Syntax: "
        echo "make_new_backup.sh arguments"
        echo "arguments:"
        echo "  --orchestration_name=<name>   example: myorchestration (from /mytenant/public/myorchestration)"
        echo "  --instance_uuid=<backup uuid>    example: 1234567890 (The backup uuid is generated by exabr)"
        echo "  --backup_date=<backup uuid>    example: 201701241910 (The backup date is generated by exabr)"
        echo "  --old_tenant_name=<tenant>    example: mytenant (from /mytenant/public/myorchestration)"
        echo "  --new_tenant_name=<tenant>    example: mytenant (from /mytenant/public/myorchestration)"
        echo "  --old_vnet_name=<vnet>      example: myvnet (from /mytenant/public/myvnet)"
        echo "  --new_vnet_name=<vnet>      example: myvnet (from /mytenant/public/myvnet)"
        exit
fi
echo orchestration name = ${ORCH}
echo instance UUID = ${INSTUUID}
echo backup date = $BACKUPDATE
echo old tenant name = ${OLDTENANT}
echo new tenant name = ${NEWTENANT}
echo old vnet name = ${OLDVNET}
echo new vnet name = ${NEWVNET}
echo

## Variables definition
BACKUPLOC="/opt/exalogic/tools/data/lifecycle/backups/orchestration"
OLDDIR=${OLDTENANT}_public_${ORCH}
NEWDIR=${NEWTENANT}_public_${ORCH}

## Steps
echo "Step 0: Pre-checks"
EXIT=false
if [ ! -d "$BACKUPLOC/$OLDDIR" ]; then
    echo "Error: Directory $BACKUPLOC/$OLDDIR does not exist"
        EXIT=true
fi
if [ ! -f "$BACKUPLOC/$OLDDIR/orchestration.json" ]; then
    echo "Error: File $BACKUPLOC/$OLDDIR/orchestration.json does not exist"
        EXIT=true
fi
if [ ! -d "$BACKUPLOC/$OLDDIR/$INSTUUID/$BACKUPDATE" ]; then
    echo "Error: Directory $BACKUPLOC/$OLDDIR/$INSTUUID/$BACKUPDATE does not exist"
        EXIT=true
fi
if ! oracle-compute list tenant $NEWTENANT | grep $NEWTENANT > /dev/null ; then
        echo "Error: New tenant not found"
        EXIT=true
fi
if ! oracle-compute list vnet $NEWTENANT/public/${NEWVNET} | grep $NEWVNET > /dev/null ; then
        echo "Error: New vnet not found"
        EXIT=true
fi
if [ -d "$BACKUPLOC/$NEWDIR" ] ; then
        echo "Error: New backup directory, $BACKUPLOC/$NEWDIR, already exists"
        EXIT=true
fi
if [ $EXIT = true ] ; then
        exit
fi

echo "Step 1: Creating new backups files in /opt/exalogic/tools/data/lifecycle/backups/orchestration"
cp -r $BACKUPLOC/$OLDDIR $BACKUPLOC/$NEWDIR

echo "Step 2: Update top-level orchestration.json"
sed -i "s/$OLDTENANT/$NEWTENANT/g" $BACKUPLOC/$NEWDIR/orchestration.json
sed -i "s/$OLDVNET/$NEWVNET/g" $BACKUPLOC/$NEWDIR/orchestration.json

echo "Step 3: Update actual orchestration.json"
sed -i "s/$OLDTENANT/$NEWTENANT/g" $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/orchestration.json
sed -i "s/$OLDVNET/$NEWVNET/g" $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/orchestration.json

echo "Step 4: Update instance.json"
sed -i '/\"hostname":/d' $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/instance.json
sed -i '/\"domain":/d' $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/instance.json
sed -i '/\"nimbula_vcable-net.\"\: \"/d' $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/instance.json
awk '/\"dns\": \[/{skip=2;next} skip>0{--skip;next} {print}' $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/instance.json > $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/new_instance.json
rm $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/instance.json
mv $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/new_instance.json $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/instance.json
sed -i "s/$OLDTENANT/$NEWTENANT/g" $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/instance.json
sed -i "s/$OLDVNET/$NEWVNET/g" $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/instance.json

echo "Step 5: Update snapshot.json"
sed -i "s/$OLDTENANT/$NEWTENANT/g" $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/snapshot.json

echo "Step 6: Update backup.info"
sed -i "s/$OLDTENANT/$NEWTENANT/g" $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE/backup.info

echo "Step 7: Generate checksums.md5"
cd $BACKUPLOC/$NEWDIR/$INSTUUID/$BACKUPDATE
mv checksums.md5 checksums.md5.old
echo 'messages "md5sum: disk?.raw: No such file or directory" should be ignored'
md5sum snapshot.json orchestration.json instance.json System.img.tgz disk1.raw disk2.raw disk3.raw disk4.raw disk5.raw \
	disk6.raw disk7.raw disk8.raw disk9.raw > checksums.md5
cd - > /dev/null

