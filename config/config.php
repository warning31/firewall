global $config;
$config = parse_config(true);
// Cron Ekleme
//if (!array_search("/usr/local/bin/mysql_check.sh", array_column($config['cron']['item'], "command"))) {
 //   $config['cron']['item'][] = array(
  //      "minute" => "*/1",
   //     "hour" => "*",
  //      "mday" => "*",
   //     "month" => "*",
    //    "wday" => "*",
 //       "who" => "root",
   //     "command" => "/usr/local/bin/mysql_check.sh"
   // );
   // write_config("Hotspot Check Cron added.");
//}




// Ana Sayfa Servis Status
if (!preg_match("/services_status/", $config['widgets']['sequence'])) {
    $config['widgets']['sequence'] = $config['widgets']['sequence'] . ",services_status:col2:open";
}
write_config("Firewall Settings added.");