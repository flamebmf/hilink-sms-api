#!/bin/bash
echo "Content-Type: text/xml"
echo ""

source /var/www/cgi-bin/huawei_hilink_api.sh
hilink_host="192.168.8.1"

_initHilinkAPI

ACTION=$(echo "$QUERY_STRING" | grep -oP 'action=\K[^&]+')

if [ "$ACTION" = "send" ]; then
    PHONE=$(echo "$QUERY_STRING" | grep -oP 'phone=\K[^&]+' | sed 's/[^0-9]//g')
    MSG=$(echo "$QUERY_STRING" | grep -oP 'msg=\K[^&]+' | sed 's/+/ /g;s/%20/ /g')
    hilink_xmldata="<?xml version='1.0' encoding='UTF-8'?><request><Index>-1</Index><Phones><Phone>$PHONE</Phone></Phones><Sca/><Content>$MSG</Content><Length>-1</Length><Reserved>-1</Reserved><Date>-1</Date></request>"
    _sendRequest "api/sms/send-sms"
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><response><ok>$(if [ "$status" = "OK" ]; then echo 1; else echo 0; fi)</ok><status>$status</status></response>"
elif [ "$ACTION" = "list" ]; then
    _sendRequest "api/sms/sms-list"
    echo "$response"
elif [ "$ACTION" = "delete" ]; then
    INDEX=$(echo "$QUERY_STRING" | grep -oP 'index=\K[^&]+')
    hilink_xmldata="<?xml version='1.0' encoding='UTF-8'?><request><Index>$INDEX</Index></request>"
    _sendRequest "api/sms/delete-sms"
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><response><ok>$(if [ "$status" = "OK" ]; then echo 1; else echo 0; fi)</ok></response>"
else
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><response><ok>1</ok><action>$ACTION</action></response>"
fi

_closeHilinkAPI "save"
SCRIPT
