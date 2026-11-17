# xym writes a NixOS image that relays VPN traffic onto a disk.
# Run it without arguments for the wizard, or use the commands below.

# ---------------------------------------------------------------------- TUI

# Wizard that asks, checks, builds and writes. All work is done by the CLI.
def main [] {
  ext-gum-style "xym"

  let hardware = (
    ext-gum-choose "Which hardware is the device?"
      (main hardware list | get name)
  )
  let vpn = (
    ext-gum-choose "Which VPN should it relay?"
      (main vpn list | get name)
  )
  tui-run "Checking this machine can build the image" {
    main hardware check $hardware
  }
  tui-run "Checking the VPN is supported" { main vpn check $vpn }

  let ddns_config = ext-gum-input "Path to your ddns-updater config.json"
  tui-run "Running ddns-updater with your config, this needs the network" {
    main ddns check $ddns_config
  }

  let wifi = tui-wifi
  let password = tui-password
  let device = tui-device

  let image = tui-run "Building the image, the first time takes long" {
    main image build $hardware $vpn
  }
  let prepared = tui-run "Putting your configuration into the image" {
    (
      main image prepare $image $hardware
        --ddns-config $ddns_config
        --wifi-ssid $wifi.ssid
        --wifi-psk $wifi.psk
        --password $password
    )
  }

  tui-confirm-erase $device
  tui-run "Writing the image" { main image write $prepared $device }
  tui-run "Cleaning up" { main image clean $prepared }

  ext-gum-style (
    "Done. Put the disk in the device and power it on, "
    + "then log in with ssh as the xym user."
  )
}

def tui-run [title: string, action: closure] {
  ext-gum-log "info" $title
  let result = try { do $action } catch { |error|
    ext-gum-log "error" $error.msg
    exit 1
  }
  print $result
  $result
}

def tui-wifi [] {
  let none = { ssid: "", psk: "" }
  if not (ext-gum-confirm "Set up a Wi-Fi connection on the device?") {
    return $none
  }
  let ssid = ext-gum-input "Wi-Fi name"
  let psk = ext-gum-input "Wi-Fi password" --password
  print (main wifi check $ssid $psk)
  { ssid: $ssid, psk: $psk }
}

def tui-password [] {
  let password = (
    ext-gum-input "Password of the xym user on the device" --password
  )
  try { main password check $password } catch { |error|
    ext-gum-log "error" $error.msg
    exit 1
  }
  let again = ext-gum-input "Repeat the password" --password
  if $password != $again {
    ext-gum-log "error" "The passwords do not match."
    exit 1
  }
  $password
}

def tui-device [] {
  let disks = main device list
  if ($disks | is-empty) {
    ext-gum-log "error" "No disks found."
    exit 1
  }
  let labels = $disks | each { |disk|
    $"($disk.path)  ($disk.size)  ($disk.model)"
  }
  let device = (
    ext-gum-choose "Which disk should be overwritten?" $labels
    | split row " "
    | first
  )
  tui-run "Checking the disk" { main device check $device }
  $device
}

def tui-confirm-erase [device: string] {
  if not (ext-gum-confirm $"Erase everything on ($device)?") {
    ext-gum-log "info" "Nothing was written."
    exit 0
  }
  let typed = ext-gum-input $"Type ($device) to confirm"
  if $typed != $device {
    ext-gum-log "error" "That does not match, nothing was written."
    exit 1
  }
}

# ---------------------------------------------------------------------- CLI

# List the supported hardware.
def "main hardware list" [] {
  registry
  | get hardware
  | transpose name spec
  | each { |row| { name: $row.name, system: $row.spec.system } }
}

# Check the hardware is supported and this machine can build its image.
def "main hardware check" [hardware: string] {
  let known = main hardware list
  let matches = $known | where name == $hardware
  if ($matches | is-empty) {
    let names = $known | get name | str join ", "
    error make {
      msg: $"unknown hardware ($hardware), expected one of: ($names)"
    }
  }

  let system = $matches | first | get system
  let host = ext-host-system
  if $host == $system {
    return {
      hardware: $hardware
      system: $system
      host: $host
      emulated: false
    }
  }

  let support = ext-emulation-support $system
  if not $support.nix {
    error make {
      msg: (
        $"nix on this machine does not build for ($system), "
        + "add it to extra-platforms"
      )
    }
  }
  if not $support.binfmt {
    error make {
      msg: (
        $"no binfmt handler for ($system) is registered, "
        + "set boot.binfmt.emulatedSystems"
      )
    }
  }
  { hardware: $hardware, system: $system, host: $host, emulated: true }
}

# List the supported VPN technologies.
def "main vpn list" [] {
  registry | get vpns | each { |name| { name: $name } }
}

# Check the VPN technologies are supported.
def "main vpn check" [...vpns: string] {
  if ($vpns | is-empty) {
    error make { msg: "pick at least one vpn" }
  }

  let known = main vpn list | get name
  let unknown = $vpns | where { |vpn| $vpn not-in $known }
  if ($unknown | is-not-empty) {
    error make {
      msg: (
        $"unknown vpn ($unknown | str join ', '), "
        + $"expected one of: ($known | str join ', ')"
      )
    }
  }
  { vpns: $vpns }
}

# List the disks of this machine.
def "main device list" [] {
  ext-lsblk
  | get blockdevices
  | where type == "disk"
  | each { |disk|
    {
      path: $disk.path
      size: ($disk.size | into filesize)
      model: ($disk.model? | default "" | str trim)
      mounted: (device-mountpoints $disk | is-not-empty)
    }
  }
}

# Check the password of the xym user is acceptable.
def "main password check" [password: string] {
  password-validate $password
}

# Check a path is a whole, unmounted, writable disk that fits the image.
def "main device check" [device: string, --min-size: filesize] {
  let resolved = ext-resolve-path $device
  let entries = (
    ext-lsblk
    | get blockdevices
    | each { |disk| device-flatten $disk }
    | flatten
  )
  let matches = $entries | where path == $resolved
  if ($matches | is-empty) {
    error make { msg: $"($device) is not a block device" }
  }

  let entry = $matches | first
  if $entry.type != "disk" {
    error make {
      msg: (
        $"($device) is a ($entry.type) and not a whole disk, "
        + "pick the disk itself"
      )
    }
  }
  if ($entry.ro? | default false) {
    error make { msg: $"($device) is read-only" }
  }

  let mountpoints = device-mountpoints $entry
  if ($mountpoints | is-not-empty) {
    error make {
      msg: (
        $"($device) is in use, "
        + $"unmount ($mountpoints | str join ', ') first"
      )
    }
  }

  let size = $entry.size | into filesize
  if $min_size != null and $size < $min_size {
    error make {
      msg: $"($device) holds ($size) but the image needs ($min_size)"
    }
  }
  {
    path: $entry.path
    size: $size
    model: ($entry.model? | default "" | str trim)
  }
}

# Check a ddns-updater config by letting ddns-updater use it for real.
def "main ddns check" [config: string] {
  let path = $config | path expand
  let parsed = try {
    ext-read-text $path | from json
  } catch {
    error make { msg: $"($path) is not valid JSON" }
  }

  let settings = if ($parsed | describe) =~ '^record' {
    $parsed.settings? | default []
  } else {
    []
  }
  let valid = (is-list $settings) and ($settings | is-not-empty)
  if not $valid {
    error make {
      msg: $"($path) needs a settings list with at least one entry"
    }
  }

  let unnamed = $settings | where { |setting|
    ($setting.provider? | default "") == ""
  }
  if ($unnamed | is-not-empty) {
    error make { msg: $"every entry of ($path) needs a provider" }
  }

  let records = $settings | length
  let result = ext-ddns-run $path
  if not $result.ok {
    error make {
      msg: $"ddns-updater could not confirm the records: ($result.detail)"
    }
  }
  { records: $records, detail: $result.detail }
}

# Report whether the Wi-Fi credentials connect. It never fails, only informs.
def "main wifi check" [ssid: string, psk: string] {
  let device = ext-wifi-idle-device
  if $device == null {
    return {
      connected: null
      detail: (
        "skipped, no idle Wi-Fi device here "
        + "and testing would drop your current connection"
      )
    }
  }
  let result = ext-wifi-connect $device $ssid $psk
  { connected: $result.ok, detail: $result.detail }
}

# Build the generic image with nix, or fetch it from the cache.
def "main image build" [hardware: string, ...vpns: string] {
  let target = main hardware check $hardware
  main vpn check ...$vpns

  let image = (
    ext-nix-build (flake-ref) $target.host "makeImage"
      (build-request $hardware $vpns)
  )
  ext-find-image $image
}

# Copy the image to a private file and configure the copy.
def "main image prepare" [
  image: string
  hardware: string
  --ddns-config: string
  --wifi-ssid: string = ""
  --wifi-psk: string = ""
  --password: string
] {
  if $ddns_config == null {
    error make { msg: "--ddns-config is required" }
  }
  if $password == null {
    error make { msg: "--password is required" }
  }

  let copy = ext-image-copy $image
  try {
    (
      main image inject $copy $hardware
        --ddns-config $ddns_config
        --wifi-ssid $wifi_ssid
        --wifi-psk $wifi_psk
        --password $password
    )
  } catch { |error|
    ext-remove-file $copy
    error make { msg: $error.msg }
  }
  $copy
}

# Write the ddns-updater config, the password and the optional Wi-Fi profile
# into an image.
def "main image inject" [
  image: string
  hardware: string
  --ddns-config: string
  --wifi-ssid: string = ""
  --wifi-psk: string = ""
  --password: string
] {
  if $ddns_config == null {
    error make { msg: "--ddns-config is required" }
  }
  if $password == null {
    error make { msg: "--password is required" }
  }
  password-validate $password

  let known = registry | get hardware
  if $hardware not-in ($known | columns) {
    error make { msg: $"unknown hardware ($hardware)" }
  }
  let label = $known | get $hardware | get rootLabel
  let targets = registry | get inject

  let wifi = if ($wifi_ssid | is-empty) {
    null
  } else {
    wifi-validate $wifi_ssid $wifi_psk
    {
      profile: (wifi-profile $wifi_ssid $wifi_psk)
      target: $targets.wifi
    }
  }

  let ddns = { source: ($ddns_config | path expand), target: $targets.ddns }
  let secret = {
    hash: (ext-hash-password $password)
    target: $targets.password
  }
  ext-inject $image $label $ddns $wifi $secret
}

# Write a prepared image to a disk, after checking the disk once more.
def "main image write" [image: string, device: string] {
  let size = ext-file-size $image
  main device check $device --min-size $size
  ext-write-image $image $device
}

# Remove a prepared image.
def "main image clean" [image: string] {
  let made_here = ($image | path dirname) == (image-dir)
  let is_image = ($image | path parse | get extension) == "img"
  if not ($made_here and $is_image) {
    error make { msg: $"($image) is not an image that xym prepared" }
  }
  ext-remove-file $image
}

# Check an address is a host name or an IPv4 address that ssh can take.
def "main address check" [address: string] {
  if not ($address =~ '^[A-Za-z0-9][A-Za-z0-9.-]*$') {
    error make {
      msg: (
        $"($address) is not a host name or an IPv4 address, "
        + "write IPv6 addresses as host names"
      )
    }
  }
  { address: $address }
}

# Build the system of a running device and switch it over to that, after
# checking the device is the hardware and an xym device.
def "main update" [address: string, hardware: string, ...vpns: string] {
  let target = main hardware check $hardware
  main vpn check ...$vpns
  main address check $address

  let session = ext-ssh-open $address
  let result = try {
    update-run $session $target $vpns
  } catch { |error|
    ext-ssh-close $session
    error make { msg: $error.msg }
  }
  ext-ssh-close $session
  $result
}

def update-run [session: record, target: record, vpns: list<string>] {
  let probe = ext-device-probe $session
  update-device-check $probe $target.system $session.address

  let toplevel = (
    ext-nix-build (flake-ref) $target.host "makeToplevel"
      (build-request $target.hardware $vpns)
  )
  if not ($toplevel =~ '^/nix/store/[A-Za-z0-9._+-]+$') {
    error make { msg: $"nix built something unexpected: ($toplevel)" }
  }

  ext-update-push $session $toplevel
  ext-update-switch $session $toplevel
  { address: $session.address, system: $toplevel }
}

def update-device-check [probe: record, system: string, address: string] {
  let expected = $system | split row "-" | first
  if $probe.arch != $expected {
    error make {
      msg: (
        $"($address) is a ($probe.arch) machine, "
        + $"but this hardware is ($expected)"
      )
    }
  }
  if not $probe.xym {
    error make {
      msg: (
        $"($address) does not look like an xym device, "
        + "it has no ddns-updater config from the installer"
      )
    }
  }
}

# The shape of the xym.hardware and xym.vpns options, without settings yet.
def build-request [hardware: string, vpns: list<string>] {
  {
    hardware: ({} | insert $hardware {})
    vpns: ($vpns | each { |vpn| {} | insert $vpn {} })
  }
}

def registry [] {
  r#'{{{registry}}}'# | from json
}

def tunables [] {
  r#'{{{tunables}}}'# | from json
}

def flake-ref [] {
  $env.XYM_FLAKE? | default r#'{{{flake}}}'#
}

# Images are too big for a temporary directory, which is often in memory.
def image-dir [] {
  let cache = $env.XDG_CACHE_HOME? | default ($env.HOME | path join ".cache")
  $env.XYM_IMAGE_DIR? | default ($cache | path join "xym")
}

def is-list [value: any] {
  ($value | describe) =~ '^(list|table)'
}

def device-flatten [device: record] {
  let children = (
    $device.children?
    | default []
    | each { |child| device-flatten $child }
    | flatten
  )
  [$device] ++ $children
}

def device-mountpoints [device: record] {
  let own = $device.mountpoints? | default [] | compact
  let nested = (
    $device.children?
    | default []
    | each { |child| device-mountpoints $child }
    | flatten
  )
  $own ++ $nested
}

def password-validate [password: string] {
  if ($password | str contains "\n") {
    error make { msg: "the password must be a single line" }
  }
  let minimum = tunables | get password | get minLength
  if ($password | str length) < $minimum {
    error make {
      msg: $"the password needs at least ($minimum) characters"
    }
  }
}

def wifi-validate [ssid: string, psk: string] {
  let bad_line = ($ssid | str contains "\n") or ($psk | str contains "\n")
  if $bad_line {
    error make {
      msg: "the Wi-Fi name and password must be a single line"
    }
  }
  let length = $psk | str length
  if $length < 8 or $length > 63 {
    error make { msg: "a WPA password has 8 to 63 characters" }
  }
}

def wifi-profile [ssid: string, psk: string] {
  let escaped = $ssid | str replace --all '\' '\\' | str replace --all ';' '\;'
  [
    "[connection]"
    "id=xym-wifi"
    $"uuid=(random uuid)"
    "type=wifi"
    "autoconnect=true"
    ""
    "[wifi]"
    "mode=infrastructure"
    $"ssid=($escaped)"
    ""
    "[wifi-security]"
    "key-mgmt=wpa-psk"
    $"psk=($psk)"
    ""
    "[ipv4]"
    "method=auto"
    ""
    "[ipv6]"
    "method=auto"
    ""
  ] | str join "\n"
}

# ---------------------------------------------------------------------- EXT

def is-fake [] {
  ($env.XYM_FAKE? | default "") not-in ["" "0" "false"]
}

def is-dry-run [] {
  ($env.XYM_DRY_RUN? | default "") not-in ["" "0" "false"]
}

# Fake devices are not real, so anything that changes the system is skipped.
def ext-skip-mutations [] {
  (is-fake) or (is-dry-run)
}

def ext-gum-style [text: string] {
  ^gum style --border rounded --padding "0 2" --bold $text
}

def ext-gum-log [level: string, message: string] {
  ^gum log --level $level $message
}

def ext-gum-choose [header: string, options: list<string>] {
  ^gum choose --header $header ...$options | str trim
}

def ext-gum-input [prompt: string, --password] {
  if $password {
    ^gum input --prompt $"($prompt): " --password | str trim
  } else {
    ^gum input --prompt $"($prompt): " | str trim
  }
}

# gum confirm answers with its exit code: 0 for yes, 1 for no
def ext-gum-confirm [prompt: string] {
  try { ^gum confirm --default=false $prompt; true } catch { false }
}

def ext-host-system [] {
  if (is-fake) {
    return "x86_64-linux"
  }
  $"($nu.os-info.arch)-($nu.os-info.name)"
}

def ext-emulation-support [system: string] {
  if (is-fake) {
    return { nix: true, binfmt: true }
  }

  let platforms = (
    ^nix --extra-experimental-features "nix-command flakes"
      config show extra-platforms
    | complete
  )
  let listed = $platforms.stdout | str trim | split row " "
  let nix = $platforms.exit_code == 0 and ($system in $listed)

  let arch = $system | split row "-" | first
  let handlers = (
    glob /proc/sys/fs/binfmt_misc/*
    | where { |handler| ($handler | path basename) =~ $arch }
  )
  let binfmt = $handlers | any { |handler|
    (open --raw $handler | lines | first) == "enabled"
  }

  { nix: $nix, binfmt: $binfmt }
}

def ext-lsblk [] {
  if (is-fake) {
    return (fake-lsblk)
  }
  (
    ^lsblk --json --bytes
      --output NAME,PATH,TYPE,SIZE,RO,RM,MODEL,MOUNTPOINTS
    | from json
  )
}

def ext-resolve-path [path: string] {
  if (is-fake) {
    return $path
  }
  $path | path expand
}

def ext-read-text [path: string] {
  if (is-fake) and not ($path | path exists) {
    return (
      '{"settings": [{"provider": "duckdns", '
      + '"domain": "fake.duckdns.org", "token": "fake"}]}'
    )
  }
  open --raw $path
}

def ext-ddns-run [config: string] {
  if (is-fake) {
    return { ok: true, detail: "fake, every record is up to date" }
  }

  let ddns = tunables | get ddns
  let seconds = $ddns.timeoutSeconds | into string
  let dir = ^mktemp --directory | str trim
  let data = $dir | path join "data"
  let log = $dir | path join "ddns-updater.log"
  mkdir $data

  let job = job spawn {
    with-env {
      CONFIG_FILEPATH: $config
      DATADIR: $data
      PERIOD: $ddns.period
      LISTENING_ADDRESS: $ddns.listeningAddress
      HEALTH_SERVER_ADDRESS: $ddns.healthAddress
    } {
      ^timeout $seconds ddns-updater out+err> $log
    }
  }

  let outcome = ddns-converge $job $ddns
  try { job kill $job }
  let detail = if $outcome.ok {
    $outcome.detail
  } else {
    $"($outcome.detail)\n(ddns-log-tail $log)"
  }
  rm --recursive --force $dir
  { ok: $outcome.ok, detail: $detail }
}

# ddns-updater leaves no trace when a record already has the right IP, so its
# files cannot tell that it worked. Asking it to update returns when its update
# cycle is done, and fails when the cycle did. A record that already has the
# right IP is not an error. Its health server then looks the record up in DNS
# and compares it with the IP it knows, which is the check that the record is
# really right.
def ddns-converge [job: int, ddns: record] {
  let deadline = (date now) + ($ddns.timeoutSeconds * 1sec)
  let update_url = $"http://($ddns.listeningAddress)/update"
  let health_url = $"http://($ddns.healthAddress)/"

  mut updated = false
  mut detail = "ddns-updater never started listening"
  while (date now) < $deadline {
    if $job not-in (job list | each { |entry| $entry.id }) {
      return { ok: false, detail: "ddns-updater stopped by itself" }
    }

    let remaining = $deadline - (date now)
    if $updated {
      let answer = ddns-get $health_url $remaining
      if $answer.reached and $answer.status == 200 {
        return {
          ok: true
          detail: "every record is updated and DNS has the right address"
        }
      }
      $detail = (
        "DNS does not have the address ddns-updater set yet: "
        + ($answer.body | str trim)
      )
    } else {
      let answer = ddns-get $update_url $remaining
      if $answer.reached and $answer.status < 300 {
        $updated = true
      } else if $answer.reached {
        return {
          ok: false
          detail: $"the update failed: ($answer.body | str trim)"
        }
      }
    }
    sleep ($ddns.pollSeconds * 1sec)
  }
  { ok: false, detail: $"not confirmed in time: ($detail)" }
}

# Never fails: a connection that is refused, because the server is not up yet,
# is an answer that was not reached.
def ddns-get [url: string, timeout: duration] {
  try {
    let response = (
      http get --full --allow-errors --max-time $timeout $url
    )
    {
      reached: true
      status: $response.status
      body: ($response.body | into string)
    }
  } catch {
    { reached: false, status: 0, body: "" }
  }
}

def ddns-log-tail [log: string] {
  let count = tunables | get ddns | get logLines
  let lines = if ($log | path exists) {
    open --raw $log | lines | last $count
  } else {
    []
  }
  $"last log lines:\n($lines | str join "\n")"
}

def ext-wifi-idle-device [] {
  if (is-fake) {
    return "wlan0"
  }
  let status = (
    ^nmcli --terse --fields DEVICE,TYPE,STATE device status
    | complete
  )
  if $status.exit_code != 0 {
    return null
  }
  let idle = (
    $status.stdout
    | lines
    | split column ":" device type state
    | where type == "wifi" and state == "disconnected"
    | each { |row| $row.device }
  )
  if ($idle | is-empty) { null } else { $idle | first }
}

def ext-wifi-connect [device: string, ssid: string, psk: string] {
  if (is-fake) {
    return { ok: true, detail: "fake, connected" }
  }
  if (is-dry-run) {
    return { ok: null, detail: "dry run, the connection was not tried" }
  }

  let timeout = tunables | get wifi | get timeoutSeconds | into string
  let result = (
    ^nmcli --wait $timeout device wifi connect $ssid
      password $psk ifname $device
    | complete
  )
  do --ignore-errors { ^nmcli connection delete id $ssid } | complete | ignore
  let output = $"($result.stdout)($result.stderr)" | str trim
  { ok: ($result.exit_code == 0), detail: $output }
}

# The request has the shape of the xym.hardware and xym.vpns options. The
# expression only parses it, so no nix code is built from data.
def ext-nix-build [
  flake: string
  system: string
  function: string
  request: record
] {
  if (is-fake) {
    return "/nix/store/fake-xym-image"
  }
  if (is-dry-run) {
    return "/nix/store/dry-run-xym-image"
  }

  # impure because getFlake only takes a locked reference when pure, and the
  # flake of a running xym is a plain store path
  let expression = (
    "{ flake, system, function, request }:"
    + " (builtins.getFlake flake).lib.${system}.${function}"
    + " (builtins.fromJSON request)"
  )
  let output = try {
    (
      ^nix --extra-experimental-features "nix-command flakes" build
        --no-link --print-out-paths --impure
        --argstr flake $flake
        --argstr system $system
        --argstr function $function
        --argstr request ($request | to json --raw)
        --expr $expression
      | lines
    )
  } catch {
    error make { msg: "nix could not build the image" }
  }
  $output | first
}

# One ssh connection is opened, and every later ssh and nix copy reuses it, so
# the password is asked once.
def ext-ssh-open [address: string] {
  let user = registry | get access | get user
  let session = {
    address: $address
    target: $"($user)@($address)"
    control: ""
  }
  if (is-fake) {
    return $session
  }

  let base = $env.XDG_RUNTIME_DIR? | default (image-dir)
  mkdir $base
  let control = (
    ^mktemp --directory $"--tmpdir=($base)" "xym-ssh.XXXXXX"
    | str trim
  )
  let opened = $session | update control $control
  try {
    ^ssh -f -N -M ...(ssh-options $opened) $opened.target
    null
  } catch {
    rm --recursive --force $control
    error make { msg: $"could not log in to ($opened.target)" }
  }
  $opened
}

def ext-ssh-close [session: record] {
  if (is-fake) {
    return
  }
  ^ssh -O exit ...(ssh-options $session) $session.target | complete | ignore
  rm --recursive --force $session.control
}

def ssh-options [session: record] {
  ["-o" $"ControlPath=($session.control)/ssh"]
}

def ext-device-probe [session: record] {
  if (is-fake) {
    return {
      arch: ($env.XYM_FAKE_DEVICE_ARCH? | default "aarch64")
      xym: true
    }
  }

  let marker = registry | get inject | get ddns
  let command = $"uname -m; if test -e ($marker); then echo xym; fi"
  let result = (
    ^ssh ...(ssh-options $session) $session.target $command
    | complete
  )
  if $result.exit_code != 0 {
    error make {
      msg: $"could not ask ($session.target): ($result.stderr | str trim)"
    }
  }
  let lines = $result.stdout | lines
  let marked = ($lines | get 1? | default "") == "xym"
  { arch: ($lines | first), xym: $marked }
}

def ext-update-push [session: record, toplevel: string] {
  if (ext-skip-mutations) {
    print $"dry run, would copy ($toplevel) to ($session.target)"
    return
  }

  let options = ssh-options $session | str join " "
  with-env { NIX_SSHOPTS: $options } {
    try {
      (
        ^nix --extra-experimental-features "nix-command flakes" copy
          --to $"ssh-ng://($session.target)" $toplevel
      )
      null
    } catch {
      error make { msg: $"nix could not copy to ($session.target)" }
    }
  }
}

# One sudo, so the password is asked once. The switch runs in its own systemd
# unit, as nixos-rebuild does it, so that losing the connection while the
# network restarts does not stop it halfway.
def ext-update-switch [session: record, toplevel: string] {
  if (ext-skip-mutations) {
    print $"dry run, would switch ($session.target) to ($toplevel)"
    return
  }

  let update = tunables | get update
  let script = (
    $"nix-env --profile ($update.systemProfile) --set ($toplevel)"
    + " && systemd-run --collect --no-ask-password --pty --quiet"
    + $" --service-type=exec --unit=($update.switchUnit) --wait"
    + $" ($toplevel)/bin/switch-to-configuration switch"
  )
  try {
    (
      ^ssh -t ...(ssh-options $session) $session.target
        sudo sh -c $"'($script)'"
    )
    null
  } catch {
    error make { msg: $"switching ($session.target) failed" }
  }
}

def ext-find-image [output: string] {
  if (ext-skip-mutations) {
    return $"($output)/sd-image/xym.img"
  }
  let images = glob $"($output)/sd-image/*.img"
  if ($images | is-empty) {
    error make { msg: $"no image found in ($output)" }
  }
  $images | first
}

# The image in the store is read-only, and a private copy is what gets edited.
def ext-image-copy [image: string] {
  let base = image-dir
  if (ext-skip-mutations) {
    return ($base | path join "dry-run.img")
  }
  mkdir $base
  let copy = (
    ^mktemp $"--tmpdir=($base)" --suffix .img "xym.XXXXXX"
    | str trim
  )
  try { ^cp --reflink=auto $image $copy; null } catch {
    rm --force $copy
    error make { msg: $"could not copy ($image)" }
  }
  $copy
}

def ext-inject [
  image: string
  label: string
  ddns: record
  wifi: any
  password: record
] {
  if (ext-skip-mutations) {
    print (
      "dry run, would write the ddns-updater config, the password "
      + $"and the Wi-Fi profile into ($image)"
    )
    return
  }

  let dir = ^mktemp --directory | str trim
  let required = [
    { source: $ddns.source, target: $ddns.target }
    {
      source: (ext-stage-file $dir "password" $password.hash)
      target: $password.target
    }
  ]
  let files = if $wifi == null {
    $required
  } else {
    $required | append {
      source: (ext-stage-file $dir "wifi" $wifi.profile)
      target: $wifi.target
    }
  }

  # every file belongs to root and only root reads it: ddns-updater gets its
  # config through systemd credentials, NetworkManager ignores profiles that
  # are not private, and the password is read at activation
  let uploads = $files | each { |file|
    [
      $"mkdir-p \"($file.target | path dirname)\""
      $"upload \"($file.source)\" \"($file.target)\""
      $"chown 0 0 \"($file.target)\""
      $"chmod 0600 \"($file.target)\""
    ]
  } | flatten
  let commands = ["run" $"mount /dev/disk/by-label/($label) /"] ++ $uploads

  let result = (
    $commands
    | str join "\n"
    | ^guestfish --rw --add $image
    | complete
  )
  rm --recursive --force $dir
  if $result.exit_code != 0 {
    error make {
      msg: $"guestfish failed: ($result.stderr | str trim)"
    }
  }
}

def ext-stage-file [dir: string, name: string, content: string] {
  let path = $dir | path join $name
  $content | save --force $path
  $path
}

def ext-hash-password [password: string] {
  if (is-fake) {
    return "$6$fake$fake"
  }

  let result = $password | ^openssl passwd -6 -stdin | complete
  if $result.exit_code != 0 {
    error make {
      msg: $"openssl could not hash the password: ($result.stderr | str trim)"
    }
  }
  $result.stdout | str trim
}

def ext-file-size [path: string] {
  if (ext-skip-mutations) and not ($path | path exists) {
    return 4GiB
  }
  ls $path | get size | first
}

def ext-write-image [image: string, device: string] {
  if (ext-skip-mutations) {
    print $"dry run, would write ($image) to ($device)"
    return { written: false }
  }

  let block = tunables | get image | get writeBlockSize
  let arguments = [
    $"if=($image)"
    $"of=($device)"
    $"bs=($block)"
    "conv=fsync"
    "status=progress"
  ]

  let writable = (^test -w $device | complete | get exit_code) == 0
  try {
    if $writable {
      ^dd ...$arguments
    } else {
      ^sudo dd ...$arguments
    }
  } catch {
    error make { msg: $"writing to ($device) failed" }
  }
  ^sync
  { written: true }
}

def ext-remove-file [path: string] {
  if (ext-skip-mutations) {
    return
  }
  rm --force $path
}

def fake-lsblk [] {
  {
    blockdevices: [
      {
        name: "sda"
        path: "/dev/sda"
        type: "disk"
        size: 31914983424
        ro: false
        rm: true
        model: "Fake SD Reader"
        mountpoints: [null]
        children: [
          {
            name: "sda1"
            path: "/dev/sda1"
            type: "part"
            size: 268435456
            ro: false
            rm: true
            model: null
            mountpoints: [null]
          }
        ]
      }
      {
        name: "nvme0n1"
        path: "/dev/nvme0n1"
        type: "disk"
        size: 512110190592
        ro: false
        rm: false
        model: "Fake NVMe"
        mountpoints: [null]
        children: [
          {
            name: "nvme0n1p1"
            path: "/dev/nvme0n1p1"
            type: "part"
            size: 512110190592
            ro: false
            rm: false
            model: null
            mountpoints: ["/"]
          }
        ]
      }
      {
        name: "loop0"
        path: "/dev/loop0"
        type: "loop"
        size: 104857600
        ro: false
        rm: false
        model: null
        mountpoints: [null]
      }
    ]
  }
}
