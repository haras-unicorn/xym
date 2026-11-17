## xym\.ddns\.healthAddress

Address of the ddns-updater health server\.

_Type:_ string

_Default:_

```nix
"127.0.0.1:9999"
```

## xym\.ddns\.listeningAddress

Address of the ddns-updater web interface\.

_Type:_ string

_Default:_

```nix
"127.0.0.1:8000"
```

## xym\.ddns\.period

How often ddns-updater checks the public IP address\.

_Type:_ string

_Default:_

```nix
"5m"
```

## xym\.dns\.forwards

Upstream resolvers CoreDNS forwards to, over TLS\.

_Type:_ list of string

_Default:_

```nix
[
  "tls://1.1.1.2%one.one.one.one"
  "tls://1.0.0.2%one.one.one.one"
  "tls://9.9.9.9%dns.quad9.net"
  "tls://76.76.2.11%p1.freedns.controld.com"
]
```

## xym\.hardware

Hardware the image is built for, as a tag with the options of that hardware\.
`null` keeps the generic modules only, which is what the container tests use\.

_Type:_ null or attribute-tagged union with choices: rpi4

_Default:_

```nix
null
```

## xym\.hardware\.rpi4

Raspberry Pi 4\.

_Type:_ submodule

## xym\.time\.servers

NTP servers for chrony\. Addresses and not names, because name resolution needs
DNSSEC and DNSSEC needs the right time\.

_Type:_ list of string

_Default:_

```nix
[
  "216.239.35.0"
  "216.239.35.4"
  "216.239.35.8"
  "216.239.35.12"
  "162.159.200.1"
  "162.159.200.123"
]
```

## xym\.vpns

VPN technologies the machine relays traffic for, each a tag with the options of
that technology\.

_Type:_ list of attribute-tagged union with choices: easytier

_Default:_

```nix
[ ]
```

_Example:_

```nix
[
  {
    easytier = {
      port = 11010;
    };
  }
]
```

## xym\.vpns\.\*\.easytier

EasyTier relay for the networks that connect to it\.

_Type:_ submodule

## xym\.vpns\.\*\.easytier\.port

TCP and UDP port the relay listens on\.

_Type:_ 16 bit unsigned integer; between 0 and 65535 (both inclusive)

_Default:_

```nix
11010
```
