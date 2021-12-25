global $config;
$config = parse_config(true);


// SSH Enable
init_config_arr(array('system', 'ssh'));
$config['system']['ssh']['enable'] = "enabled";
write_config("Enabled sshd");
send_event("service reload sshd");


