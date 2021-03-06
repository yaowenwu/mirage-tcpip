type error =
  | Too_short
  | Unusable
  | Unknown_code of Cstruct.uint16
  | Bad_mac of string list

type t = {
  op: Arpv4_wire.op;
  sha: Macaddr.t;
  spa: Ipaddr.V4.t;
  tha: Macaddr.t;
  tpa: Ipaddr.V4.t;
}

let string_of_error = function
  | Too_short -> "buffer too short to be a valid arpv4 header"
  | Unusable -> "arpv4 message is not for ipv4 -> ethernet"
  | Unknown_code i -> Printf.sprintf "arpv4 message has unknown code %d" i
  | Bad_mac macs ->
    Printf.sprintf "arpv4 message with invalid MAC[s]: %S" @@ String.concat ", " macs

let pp_error formatter e = Format.fprintf formatter "%s" @@ string_of_error e

let of_cstruct buf =
  let open Arpv4_wire in
  let open Rresult in
  let check_len buf =
    if (Cstruct.len buf) < sizeof_arp then (Result.Error Too_short) else
      Result.Ok buf
  in
  let check_types buf =
    (* we only know how to deal with ethernet <-> IPv4 *)
    if get_arp_htype buf <> 1 || get_arp_ptype buf <> 0x0800 
       || get_arp_hlen buf <> 6 || get_arp_plen buf <> 4 then Result.Error Unusable
    else Result.Ok buf
  in
  let check_op buf = match get_arp_op buf |> Arpv4_wire.int_to_op with
    | Some op -> Result.Ok op
    | None -> Result.Error (Unknown_code (get_arp_op buf))
  in
  check_len buf >>= check_types >>= check_op >>= fun op ->
  let src_mac = copy_arp_sha buf in
  let target_mac = copy_arp_tha buf in
  match (Macaddr.of_bytes src_mac, Macaddr.of_bytes target_mac) with
  | None, None   -> Result.Error (Bad_mac [ src_mac ; target_mac ])
  | None, Some _ -> Result.Error (Bad_mac [ src_mac ])
  | Some _, None -> Result.Error (Bad_mac [ target_mac ])
  | Some src_mac, Some target_mac ->
    let src_ip = Ipaddr.V4.of_int32 (get_arp_spa buf) in
    let target_ip = Ipaddr.V4.of_int32 (get_arp_tpa buf) in
    Result.Ok { op;
                sha = src_mac; spa = src_ip;
                tha = target_mac; tpa = target_ip
              }
