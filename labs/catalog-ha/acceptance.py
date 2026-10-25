#!/usr/bin/env python3
"""Isolated PostgreSQL replication/fencing experiment, NOT a production HA controller.
No host ports, existing containers, databases or volumes are used.
"""
import itertools
import json
import subprocess
import time
import uuid

PREFIX = 'ecad-ha-test-' + uuid.uuid4().hex[:10]
NETWORK = PREFIX + '-net'
IMAGE = 'postgres:16-alpine'
NODES = [PREFIX + '-' + str(n) for n in range(3)]
created = []

def command(*args, check=True, timeout=35):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=timeout)

def docker(*args, **kwargs):
    return command('docker', *args, **kwargs)

def sql(node, query, check=True):
    return docker('exec', node, 'psql', '-U', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1', '-c', query, check=check)

def wait(check, description, seconds=40):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        try:
            if check(): return
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired): pass
        time.sleep(.2)
    raise AssertionError('Timed out: '+description)

def replica(name, leader):
    # Disposable anonymous volume owned by postgres; trust auth exists only in this isolated lab network.
    docker('run','-d','--name',name,'--network',NETWORK,'--user','postgres','--entrypoint','sh',IMAGE,'-ec',
        'chmod 700 /var/lib/postgresql/data; pg_basebackup -c fast -d "host='+leader+' user=postgres application_name='+name+'" -D /var/lib/postgresql/data -R -X stream; exec postgres')
    if name not in created: created.append(name)
    try:
        wait(lambda:sql(name,'SELECT pg_is_in_recovery()').stdout.strip()=='t','replica starts')
    except Exception:
        print(docker('logs',name,check=False).stderr,flush=True)
        print(docker('logs',name,check=False).stdout,flush=True)
        raise

def admissible_promotion(voters, caught_up, fenced):
    # Specification decision, not an implementation of distributed consensus.
    return len(voters)>=2 and caught_up and fenced

start=time.monotonic()
try:
    # All membership partitions and safety preconditions: no quorum or no fence => no promotion.
    cases=0
    for count in range(4):
        for voters in itertools.combinations(range(3),count):
            for caught_up,fenced in itertools.product([False,True],repeat=2):
                permitted=admissible_promotion(voters,caught_up,fenced)
                assert not permitted or (count>=2 and caught_up and fenced)
                if not fenced: assert not permitted
                cases+=1
    docker('network','create','--internal',NETWORK)
    leader, candidate, follower=NODES
    docker('run','-d','--name',leader,'--network',NETWORK,'-e','POSTGRES_HOST_AUTH_METHOD=trust',IMAGE,
           'postgres','-c','synchronous_commit=remote_apply')
    created.append(leader)
    wait(lambda:sql(leader,'SELECT 1').stdout.strip()=='1','leader starts')
    docker('exec',leader,'sh','-ec','echo "host replication all all trust" >> "$PGDATA/pg_hba.conf"')
    sql(leader,'SELECT pg_reload_conf()')
    sql(leader,"ALTER SYSTEM SET synchronous_commit='remote_apply'")
    sql(leader,'SELECT pg_reload_conf()')
    sql(leader,'CREATE TABLE catalog_probe(id integer PRIMARY KEY, value text NOT NULL)')
    replica(candidate,leader)
    replica(follower,leader)
    sql(leader,f'''ALTER SYSTEM SET synchronous_standby_names='ANY 2 ("{candidate}", "{follower}")' ''')
    sql(leader,'SELECT pg_reload_conf()')
    wait(lambda:sql(leader,"SELECT count(*) FROM pg_stat_replication WHERE sync_state='quorum'").stdout.strip()=='2','two sync readers')
    sql(leader,"INSERT INTO catalog_probe VALUES (1,'acknowledged before fault')")
    acknowledged=sql(leader,'SELECT json_agg(catalog_probe ORDER BY id) FROM catalog_probe').stdout.strip()
    # Both read endpoints have applied the acknowledged commit before success returns.
    for node in [candidate,follower]:
        assert sql(node,'SELECT json_agg(catalog_probe ORDER BY id) FROM catalog_probe').stdout.strip()==acknowledged
        assert sql(node,"INSERT INTO catalog_probe VALUES (9,'forbidden')",check=False).returncode!=0
    docker('network','disconnect',NETWORK,leader)
    # A TCP-isolated old leader is still a writer locally. Quorum alone cannot fence it.
    assert sql(leader,'SELECT pg_is_in_recovery()').stdout.strip()=='f'
    assert not admissible_promotion({1,2},True,False)
    # No new acknowledged commit is possible with missing synchronous peers.
    blocked=subprocess.Popen(['docker','exec',leader,'psql','-U','postgres','-At','-v','ON_ERROR_STOP=1','-c',"INSERT INTO catalog_probe VALUES (2,'unacknowledged')"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    wait(lambda:sql(leader,"SELECT count(*) FROM pg_stat_activity WHERE wait_event='SyncRep'").stdout.strip()=='1','write blocked on replication')
    assert blocked.poll() is None
    # Explicit process fencing must succeed and be observed before promotion.
    fault_start=time.monotonic()
    docker('stop','--time','3',leader)
    blocked.communicate(timeout=10)
    assert blocked.returncode!=0
    assert docker('inspect','--format','{{.State.Running}}',leader).stdout.strip()=='false'
    assert admissible_promotion({1,2},True,True)
    sql(candidate,'SELECT pg_promote(true,10)')
    assert sql(candidate,'SELECT pg_is_in_recovery()').stdout.strip()=='f'
    assert sql(candidate,'SELECT json_agg(catalog_probe ORDER BY id) FROM catalog_probe').stdout.strip()==acknowledged
    # Recreate only this disposable follower to follow the new timeline.
    docker('rm','-fv',follower)
    replica(follower,candidate)
    sql(candidate,f'''ALTER SYSTEM SET synchronous_standby_names='ANY 1 ("{follower}")' ''')
    sql(candidate,'SELECT pg_reload_conf()')
    wait(lambda:sql(candidate,"SELECT count(*) FROM pg_stat_replication WHERE sync_state='quorum'").stdout.strip()=='1','new sync reader')
    sql(candidate,"INSERT INTO catalog_probe VALUES (3,'acknowledged after failover')")
    outage_seconds=round(time.monotonic()-fault_start,2)
    # Old leader's divergent, unacknowledged transaction is discarded only in this lab.
    # Production requires backup/rewind policy. It must never restart as writable primary.
    docker('rm','-fv',leader)
    replica(leader,candidate)
    assert sql(leader,'SELECT pg_is_in_recovery()').stdout.strip()=='t'
    expected=sql(candidate,'SELECT json_agg(catalog_probe ORDER BY id) FROM catalog_probe').stdout.strip()
    assert sql(leader,'SELECT json_agg(catalog_probe ORDER BY id) FROM catalog_probe').stdout.strip()==expected
    assert sql(leader,"INSERT INTO catalog_probe VALUES (4,'forbidden')",check=False).returncode!=0
    assert sql(candidate,'SELECT count(*) FROM catalog_probe WHERE id=2').stdout.strip()=='0'
    print(json.dumps({'result':'PASS','postgres':IMAGE,'precondition_cases':cases,
        'acknowledged_rows_preserved':2,'rejoined_old_leader':'read-only replica',
        'measured_manual_failover_seconds':outage_seconds,'elapsed_seconds':round(time.monotonic()-start,2),
        'limits':'single-host lab, externally verified process fencing, no distributed controller or production HA claim'},indent=2),flush=True)
finally:
    for node in reversed(created): docker('rm','-fv',node,check=False)
    docker('network','rm',NETWORK,check=False)
