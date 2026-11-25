#!/usr/bin/env python3
"""Prepare a private per-machine named-tunnel deployment profile.
Run on the trusted Cloudflare management machine, not on the new host.
No secrets are printed. The CF account API token never leaves this machine.
The default is a read-only preview; --apply performs narrowly scoped creation.
"""
import argparse, json, os, pathlib, re, urllib.parse, urllib.request, urllib.error

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--account-id', required=True)
    p.add_argument('--zone-id', required=True)
    p.add_argument('--api-token-file', required=True)
    p.add_argument('--hostname', required=True)
    p.add_argument('--profile', required=True, help='New private output JSON path')
    p.add_argument('--name', default='')
    p.add_argument('--port', type=int, default=7676)
    p.add_argument('--bark-file', help='Optional existing private Bark configuration JSON')
    p.add_argument('--apply', action='store_true')
    a = p.parse_args()
    host = a.hostname.lower().strip().rstrip('.')
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?', host) or '.' not in host:
        raise SystemExit('Invalid hostname')
    if not 1024 <= a.port <= 65535:
        raise SystemExit('Invalid local port')
    for value in (a.account_id, a.zone_id):
        if not re.fullmatch(r'[a-fA-F0-9]{32}', value):
            raise SystemExit('Invalid Cloudflare identifier')
    target = pathlib.Path(a.profile).expanduser().absolute()
    if target.exists():
        raise SystemExit('Profile already exists: refuse overwrite')
    token = pathlib.Path(a.api_token_file).expanduser().read_text().strip()
    def api(method, path, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(
            'https://api.cloudflare.com/client/v4' + path, data=data, method=method,
            headers={'Authorization': 'Bearer '+token, 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                result = json.load(response)
        except urllib.error.HTTPError as exc:
            raise RuntimeError('Cloudflare HTTP '+str(exc.code)+' for '+method+' '+path.split('?')[0]) from None
        if not result.get('success'):
            raise RuntimeError('Cloudflare API rejected '+method+' '+path.split('?')[0])
        return result.get('result')
    zone = api('GET', '/zones/'+a.zone_id)
    if zone.get('status')!='active' or not host.endswith('.'+zone['name']):
        raise SystemExit('Hostname does not belong to the selected active zone')
    base = '/accounts/'+a.account_id+'/cfd_tunnel'
    name = 'devspace-oneclick-'+host
    matches = [x for x in api('GET', base+'?is_deleted=false&per_page=100') if x.get('name')==name]
    records = api('GET','/zones/'+a.zone_id+'/dns_records?name='+urllib.parse.quote(host))
    if len(matches)>1 or len(records)>1:
        raise SystemExit('Ambiguous tunnel or DNS records; no changes made')
    tunnel = matches[0] if matches else None
    if records and (not tunnel or records[0]['type']!='CNAME' or records[0]['content']!=tunnel['id']+'.cfargotunnel.com' or not records[0].get('proxied')):
        raise SystemExit('Existing DNS belongs to another service; refuse overwrite')
    ingress = [{'hostname':host,'service':'http://127.0.0.1:'+str(a.port),'originRequest':{}},{'service':'http_status:404'}]
    def verify_config(tid):
        cfg = api('GET',base+'/'+tid+'/configurations') or {}
        return (cfg.get('config') or {}).get('ingress') == ingress
    if tunnel and not verify_config(tunnel['id']):
        raise SystemExit('Existing tunnel ingress differs; refuse overwrite')
    bark = None
    if a.bark_file:
        bark = json.loads(pathlib.Path(a.bark_file).expanduser().read_text())
        if not isinstance(bark,dict) or not str(bark.get('server','')).startswith('https://') or not bark.get('deviceKey') or len(str(bark.get('encryptionKey','')).encode()) not in (16,24,32):
            raise SystemExit('Invalid private Bark CBC configuration')
    print(json.dumps({'hostname':host,'named_tunnel_exists':bool(tunnel),'dns_exists':bool(records),'local_port':a.port,'apply':a.apply,'profile_destination':str(target)}))
    if not a.apply:
        return
    if not tunnel:
        tunnel = api('POST',base,{'name':name,'config_src':'cloudflare'})
        api('PUT',base+'/'+tunnel['id']+'/configurations',{'config':{'ingress':ingress}})
    tid = tunnel['id']
    if not verify_config(tid):
        raise SystemExit('Tunnel configuration readback failed')
    if not records:
        api('POST','/zones/'+a.zone_id+'/dns_records',{'name':host,'type':'CNAME','content':tid+'.cfargotunnel.com','proxied':True,'ttl':1})
    dns = api('GET','/zones/'+a.zone_id+'/dns_records?name='+urllib.parse.quote(host))
    if len(dns)!=1 or dns[0]['content']!=tid+'.cfargotunnel.com' or not dns[0]['proxied']:
        raise SystemExit('DNS readback failed')
    connector = api('GET',base+'/'+tid+'/token')
    if isinstance(connector,dict):
        connector = connector.get('token')
    if not isinstance(connector,str) or len(connector)<32:
        raise SystemExit('Named connector token unavailable')
    profile={'mode':'named','name':a.name or host,'publicUrl':'https://'+host,'port':a.port,'tunnelToken':connector}
    if bark: profile['bark']=bark
    target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w',encoding='utf8') as f: json.dump(profile,f,indent=2)
    print('PRIVATE_PROFILE_READY; transfer using an authorized private channel. Do not upload the profile to GitHub or chat.')
if __name__=='__main__':
    try:
        main()
    except Exception as exc:
        raise SystemExit('Provisioning failed: '+str(exc))

