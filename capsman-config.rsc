:local wifiSetting {
 1={ ssid="Home"; pass="123456789"; wpa=; hide=; vlan=; "client-isolation"=; wps= }
};

:local mode "S";
:local identity { "name"=""; "mode"=; "board-name"= };

:local datapathBridge "bridge1";

:local wifiBand {
 "2"={
  "extended-ssid"=""
  "channel.bandV3"=""
  "channel.bandV2"="2ghz-g/n"
  "channel.widthV3"=""
  "channel.widthV2"=""
  "channel.frequencyV3"="2412-2462:25"
  "channel.frequencyV2"="2412,2437,2462"
  "countryV2"="united states3"
  "countryV3"="United States"
 };
 "5"={
  "extended-ssid"=""
  "channel.bandV3"=""
  "channel.bandV2"=""
  "channel.widthV3"=""
  "channel.widthV2"=""
  "channel.frequencyV3"="5180-5240:20, 5745-5805:20"
  "channel.frequencyV2"="5180,5200,5220,5240,5260,5280,5300,5320"
  "countryV2"="united states3"
  "countryV3"="United States"
 }
};

:local scriptVersion "3.01";

### CAPsMAN V2+V3, RouterOS 7.14+ ###
### Stanislav Habich              ###
### stanislavhabich@gmail.com     ###

### wifiSetting ###
# cislo ( 1-8 cislo ): poradi SSID, pro vic ssid duplikuj radek na dalsi samostatny radek a zmen prvni poradove cislo na dalsi v poradi.
# - cislo 8 ma extra funkci ktera nastavi CAP jednotku s qcom balickem tak, ze toto SSID vysila kdyz CAP neni pripojen k CAPsMANu.
# ssid: nazev bezdratove site
# pass ( 0, 8-63 znaku ): wifi heslo. Bez zadaneho hesla se vypne wpa
# wpa ( 23 | 3 ; Default: "" ): podle cisla se vynuti typ wpa, default je "wpa2-psk"
# hide ( 1 ; Default: "" ): 1 aktivuje skryte ssid
# vlan ( 2-4095 ; Default: "" ): aktivace vlan, data z daneho ssid se vkladaji do vlan
# client-isolation ( 1 ; Default: "" ): 1 aktivuje izolaci klientu
# wps ( 1 ; Default: "" ): 1 aktivuje WPS

### mode ###
# S  - SERVER, pouze CAPsMAN server, nenastavuje lokalni interface (CPE - Disc / SXT..)
# S2 - SERVER a LOCAL interface, CAPsMAN server + local configuration wifi (home ap - hAP, cAP..)
# C  - CLIENT, pouze CAP v L3 rezimu (CAPsMAN server pridelovany pres DHCP)
# C2 - CLIENT, pouze CAP v L2 rezimu (discovery inteface)
# D  - DISABLE, disable and delete CAPsMAN a CAP a LOCAL

### identity ###
# name ( Default: "" ): nazev pridany do identity zarizeni ( popis zarizeni, umisteni.. )
# mode ( 1; Default: "" ): pridat aktualni mod do identity
# board-name ( 1; Default: "" ): prida nazev boardu do identity
### pokud neni vyplnena ani jedna polozka, identita se nezmeni

### wifiBand ###
# extended-ssid ( Default: "" ): pripona za ssid
# channel.bandV3 ( /interface wifi configuration/add channel.band= ; Default: "" ): vynuceny bezdratovy standard
# channel.bandV2 ( /caps-man configuration add channel.band= ; Default: "" ): vynuceny bezdratovy standard
# channel.widthV3 ( /interface wifi configuration add channel.width= ; Default: "" ): sirka kanalu, default je maximalni sirka
# channel.widthV2 ( /caps-man configuration add channel.extension-channel= ; Default: "" ): sirka kanalu, default je maximalni sirka
# channel.frequency: Rozsah pro automatickou volbu kanalu

# datapathBridge - do jakeho bridge pridat wifi interface, typicky to je bridge1. Neplati pro mode S

### predpoklada se, ze ###
# pro mode S a S2: existuje na zarizeni DHCP server
# pro mode S2: existuji lokalni wifi interface ktere lze zaradit do capsman
# pro mode C a C2: existuje v siti dalsi zarizeni v mode S nebo S2
# pro mode S2, C a C2: existuje interface zvoleny v "datapathBridge"

# -------------------------------------------------------------------------------------------------------------------------- #

### servisni SSID: zakomentuj pro vypnuti, jinak nahradi ssid s cislem 8 ###
#:set wifiSetting ($wifiSetting, { 8={ ssid="servis"; pass="servisservis"; wpa=; hide=1; vlan=; "client-isolation"= } } );

# -------------------------------------------------------------------------------------------------------------------------- #

:if ([/system script job print count-only as-value where script=[:jobname] ] > 1) do={
 /log error "script instance already running"; :error "script instance already running";
}

/log warning "capsman-config RUN";
/log warning ("capsman-config version:".$scriptVersion);
/log warning ("capsman-config mode:".$mode);

# validace
:if ( $mode != "C" && $mode != "C2" && $mode != "D" ) do={
 :foreach kS,vS in=$wifiSetting do={
  :if ([:len ($vS->"ssid")] = 0)                             do={ /log error ("SSID-".$kS." - ssid is short!!"); quit; }; # kontrola ssid
  :if ([:len ($vS->"pass")] > 0 && [:len ($vS->"pass")] < 8 ) do={ /log error ("SSID-".$kS." - password is short!!"); quit; }; # kontrola pass
 }
}

# prepare
:foreach i in=[/ip dhcp-server network find] do={/ip dhcp-server network set $i caps-manager=[/ip dhcp-server network get $i gateway]};
/system leds set type=off [find where leds=user-led];

# cleaning capsman and cap v3
:do { [:parse " \
 /interface wifi capsman/set enabled=no; \
 /interface wifi cap set enabled=no discovery-interfaces=\"\"; \
"] } on-error={ };

:if ( $mode != "S" ) do={
 :do { [:parse "/interface wifi remove [find where master-interface]; /interface wifi reset [find where master]; :delay 1;"] } on-error={ }
};

:do { [:parse " \
 /interface wifi provisioning remove [find]; \
 /interface wifi configuration remove [find]; \
 /interface wifi datapath remove [find]; \
 /interface wifi datapath add disabled=no name=capdp; \
"] } on-error={ };

# cleaning capsman and cap v2
:do { [:parse " \
 /caps-man manager set enabled=no; \
 /interface wireless cap set enabled=no caps-man-addresses=\"\" bridge=none discovery-interfaces=\"\" interfaces=\"\"; \
 /caps-man provisioning remove [find]; \
 /caps-man configuration remove [find]; \
"] } on-error={ };

# generovani konfigurace
:local setConfiguration do={
 :foreach kS,vS in=$wifiSetting do={
  :foreach kB,vB in=$wifiBand do={
   :if ( $mode = "S" or $mode = "S2" or $kS = 8 ) do={
    :local nameConfiguration ($kS."-".$kB."g");
    :local wifiV3 ("/interface wifi configuration add disabled=no datapath=capdp");
    :local wifiV2 ("/caps-man configuration add");
    :local wifiExtV3 [:toarray ""];
    :local wifiExtV2 [:toarray ""];

    :set ($wifiExtV3->"name")                           $nameConfiguration;
    :set ($wifiExtV2->"name")                           $nameConfiguration;

    :set ($wifiExtV3->"ssid")                           ( "\"".$vS->"ssid".$vB->"extended-ssid"."\"" );
    :set ($wifiExtV2->"ssid")                           ( "\"".$vS->"ssid".$vB->"extended-ssid"."\"" );

    :set ($wifiExtV3->"country")                        ( "\"".$vB->"countryV3"."\"" );
    :set ($wifiExtV2->"country")                        ( "\"".$vB->"countryV2"."\"" );

    :set ($wifiExtV3->"channel.frequency")              ( "\"".$vB->"channel.frequencyV3"."\"" );
    :set ($wifiExtV2->"channel.frequency")              ( "\"".$vB->"channel.frequencyV2"."\"" );

    :if ( [:len ($vB->"channel.bandV3")] > 0 )   do={ :set ($wifiExtV3->"channel.band") ($vB->"channel.bandV3"); };
    :if ( [:len ($vB->"channel.bandV2")] > 0 )   do={ :set ($wifiExtV2->"channel.band") ($vB->"channel.bandV2"); };

    :if ( [:len ($vB->"channel.widthV3")] > 0 )  do={ :set ($wifiExtV3->"channel.width") ($vB->"channel.widthV3"); };
    :if ( [:len ($vB->"channel.widthV2")] > 0 )  do={ :set ($wifiExtV2->"channel.extension-channel") ($vB->"channel.widthV2"); };

    :if ( [:len ($vS->"pass")] >= 8 ) do={
     :set ($wifiExtV3->"security.passphrase")           ( "\"".$vS->"pass"."\"" );
     :set ($wifiExtV2->"security.passphrase")           ( "\"".$vS->"pass"."\"" );

     :set ($wifiExtV3->"security.authentication-types") "wpa2-psk";
     :set ($wifiExtV2->"security.authentication-types") "wpa2-psk";
     :if ( ($vS->"wpa") = 23 ) do={ :set ($wifiExtV3->"security.authentication-types") "wpa2-psk,wpa3-psk" };
     :if ( ($vS->"wpa") = 3 ) do={ :set ($wifiExtV3->"security.authentication-types") "wpa3-psk" };
    };

    :if ( ($wifiExtV3->"security.authentication-types") = "wpa2-psk" ) do={
     :set ($wifiExtV3->"security.management-protection") "disabled";
    }

    :if ( ($vS->"vlan") > 1 && ($vS->"vlan") < 4096 ) do={
     :set ($wifiExtV3->"datapath.vlan-id") ($vS->"vlan");
     :set ($wifiExtV2->"datapath.vlan-id") ($vS->"vlan");
     :set ($wifiExtV2->"datapath.vlan-mode") "use-tag";
    };

    :if ( ($vS->"hide") = 1 ) do={
     :set ($wifiExtV3->"hide-ssid") "yes";
     :set ($wifiExtV2->"hide-ssid") "yes";
    };

    :if ( ($vS->"client-isolation") = 1 ) do={
     :set ($wifiExtV3->"datapath.client-isolation") "yes";
    } else={
     :set ($wifiExtV2->"datapath.client-to-client-forwarding") "yes";
    };

    :if ( ($vS->"wps") != 1 ) do={
     :set ($wifiExtV3->"security.wps") "disable";
    };

    :set ($wifiExtV3->"security.ft")                    "yes";
    :set ($wifiExtV3->"security.ft-over-ds")            "yes";
    :set ($wifiExtV3->"multicast-enhance")              "enabled";

    :set ($wifiExtV2->"datapath.local-forwarding")      "yes";
    :set ($wifiExtV2->"security.encryption")            "aes-ccm";
    :set ($wifiExtV2->"security.group-key-update")      "24h";

    :foreach kE,vE in=$wifiExtV3 do={ :set wifiV3 ($wifiV3." ".$kE."=".$vE); };
    :foreach kE,vE in=$wifiExtV2 do={ :set wifiV2 ($wifiV2." ".$kE."=".$vE); };

    :do { [:parse $wifiV3] } on-error={ };
    :do { [:parse $wifiV2] } on-error={ };
   }
  }
 }
};

# nastaveni provisioning
:local setProvisioning do={
 :foreach kB,vB in=$wifiBand do={
  :local masterConfiguration "";
  :local slaveConfiguration "";
  :local wifiDefV3 ("/interface wifi provisioning add action=create-dynamic-enabled disabled=no supported-bands=\"".($kB."ghz-n")."\" name-format=\"c$kB-%I-%C\"");
  :local wifiDefV2 ("/caps-man provisioning add action=create-dynamic-enabled disabled=no name-format=prefix-identity name-prefix=c".$kB);
  :if ( $kB = 2 ) do={
   :set wifiDefV2 ($wifiDefV2." hw-supported-modes=b,g,gn");
  } else={
   :set wifiDefV2 ($wifiDefV2." hw-supported-modes=a,an,ac");
  }
  :foreach kS,vS in=$wifiSetting do={
   :if ( $kS = 1 ) do={
    :set masterConfiguration ("master-configuration=".$kS."-".$kB."g");
   } else {
    :if ( [:len $slaveConfiguration] > 0 ) do={
      :set slaveConfiguration ($slaveConfiguration.",".$kS."-".$kB."g");
     } else={
      :set slaveConfiguration ("slave-configurations=".$kS."-".$kB."g");
     }
   }
  }
  :set wifiDefV3 ($wifiDefV3." ".$masterConfiguration." ".$slaveConfiguration);
  :set wifiDefV2 ($wifiDefV2." ".$masterConfiguration." ".$slaveConfiguration);

  :do { [:parse $wifiDefV3] } on-error={ };
  :do { [:parse $wifiDefV2] } on-error={ };
 }
};

# nastaveni lokalnich interface
:local setLocalWifi do={
 # V3
 :local wifiDef (" \
  :local ifaceMap [:toarray \"\"]; \
  :if ( [/interface find name=wifi1] ) do={ \
   :foreach i in=[/interface wifi radio find] do={ \
    :set (\$ifaceMap->[:pick [/interface wifi radio get \$i bands as-string] 0 1]) ([/interface wifi radio get \$i interface as-string]); \
   }; \
  }; \
  :return [:serialize to=json \$ifaceMap]; \
 ");

 :local ifaceMap [:toarray ""];
 :do { :set ifaceMap [:deserialize from=json [[:parse $wifiDef]]] } on-error={ };

 :foreach kM,vM in=$ifaceMap do={
  :local ifaceMaster 1;
  :foreach kS,vS in=$wifiSetting do={
   :if ( $mode = "S2" or $kS = 8 ) do={
    :local nameConfiguration ($kS."-".$kM."g");
    :local nameInterface ("c".$kM."-local-".$kS);
    :local manager "local";
    :if ( $mode != "S2" ) do={ :set manager "capsman-or-local"; }
    :if ( $ifaceMaster = 1 ) do={
     :do { [:parse "/interface wifi set [find default-name=\"$vM\"] configuration=\"$nameConfiguration\" configuration.manager=$manager configuration.mode=ap disabled=no name=\"$nameInterface\";"] } on-error={ };
    } else={
     :do { [:parse "/interface wifi add configuration=\"$nameConfiguration\" configuration.mode=ap disabled=no master-interface=[find default-name=\"$vM\"] name=\"$nameInterface\";"] } on-error={ };
    }
    :set ifaceMaster ($ifaceMaster + 1);
   }
  }
  :if ( $ifaceMaster = 1 ) do={
    :do { [:parse "/interface/wifi/set [find default-name=\"$vM\"] configuration.manager=capsman configuration.mode=ap datapath=capdp;"] } on-error={ };
  }
 }
};

# nastaveni identity
:local nameIdentity "";
:if ( ($identity->"mode") ) do={
 :if ( [:len $nameIdentity] > 0 ) do={ :set nameIdentity ($nameIdentity."-") }
 :set nameIdentity ($nameIdentity.$mode);
}

:if ( [:len ($identity->"name") ] > 0 ) do={
 :if ( [:len $nameIdentity] > 0 ) do={ :set nameIdentity ($nameIdentity."-") }
 :set nameIdentity ($nameIdentity.$identity->"name");
}

:if ( ($identity->"board-name") ) do={
 :if ( [:len $nameIdentity] > 0 ) do={ :set nameIdentity ($nameIdentity."-") }
 :set nameIdentity ($nameIdentity.[/system resource get board-name]);
}

:local identityDef ("/system identity set name=\"$nameIdentity\"");
:if ( [:len $nameIdentity] > 0 ) do={
 :do { [:parse $identityDef] } on-error={ };
}

# CAP / CAP2
:if ( $mode = "C" or $mode = "C2" ) do={

 # V3
 :do { [:parse "/interface wifi datapath set capdp bridge=$datapathBridge;"] } on-error={ };

 $setConfiguration wifiSetting=$wifiSetting wifiBand=$wifiBand mode=$mode;
 $setLocalWifi wifiSetting=$wifiSetting wifiBand=$wifiBand mode=$mode;

 :if ( $mode = "C" ) do={
  :do { [:parse "/interface wifi cap set enabled=yes slaves-datapath=capdp discovery-interfaces=\"\";"] } on-error={ };
 } else={
  :do { [:parse "/interface wifi cap set enabled=yes slaves-datapath=capdp discovery-interfaces=$datapathBridge;"] } on-error={ };
 }

 # V2
 :do { [:parse "/interface wireless cap set interfaces=[/interface wireless find] bridge=$datapathBridge;"] } on-error={ };

 :if ( $mode = "C" ) do={
  :do { [:parse "/interface wireless cap set enabled=yes discovery-interfaces=\"\";"] } on-error={ };
 } else={
  :do { [:parse "/interface wireless cap set enabled=yes discovery-interfaces=$datapathBridge;"] } on-error={ };
 }

 /system leds set type=ap-cap [find where leds=user-led];
}

# CAPsMAN
:if ( $mode = "S" ) do={
 $setConfiguration wifiSetting=$wifiSetting wifiBand=$wifiBand mode=$mode;
 $setProvisioning wifiSetting=$wifiSetting wifiBand=$wifiBand;

 :do { [:parse "/interface wifi capsman set enabled=yes"] } on-error={ };
 :do { [:parse "/caps-man manager set enabled=yes;"] } on-error={ };

 /system leds set type=on [find where leds=user-led];
}

# CAPsMAN + LOCAL
:if ( $mode = "S2" ) do={
 :do { [:parse "/interface wifi datapath set capdp bridge=$datapathBridge;"] } on-error={ };

 $setConfiguration wifiSetting=$wifiSetting wifiBand=$wifiBand mode=$mode;
 $setProvisioning wifiSetting=$wifiSetting wifiBand=$wifiBand;
 $setLocalWifi wifiSetting=$wifiSetting wifiBand=$wifiBand mode=$mode;
 :do { [:parse "/interface wireless cap set enabled=yes interfaces=[/interface wireless find] caps-man-addresses=127.0.0.1 bridge=$datapathBridge;"] } on-error={ };

 :do { [:parse "/interface wifi capsman set enabled=yes"] } on-error={ };
 :do { [:parse "/caps-man manager set enabled=yes;"] } on-error={ };

 /system leds set type=on [find where leds=user-led];
}

/log warning "capsman-config OK";
