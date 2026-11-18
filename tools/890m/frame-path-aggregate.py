import sys, glob, os, importlib.util, collections
spec = importlib.util.spec_from_file_location("r", sys.argv[1]); r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
d = sys.argv[2]
acc, gpu, st = {}, {}, {}
for g in sorted(glob.glob(d + "/gpu-*.txt")):
    a = g.replace("/gpu-", "/accel-")
    if not os.path.exists(a): continue
    acc.update(r.read_accel(a)); gg, head, s = r.read_gpu(g); gpu.update(gg)
    for x in s: st[(x["kind"], x["t0"])] = x
    last = head
P = 1000/120
rows = []
for seq in sorted(set(acc) & set(gpu)):
    a, g = acc[seq], gpu[seq]
    R = dict(seq=seq, gpu=r.d(a["cpend"], a["gend"]), wake=r.d(a["gend"], a["pdone"]), handoff=r.d(a["pdone"], a["fence"]),
             pipe=r.d(a["fence"], g["sub0"]), worker=r.d(g["sub0"], g["armed"]), scanout=r.d(g["armed"], g["pflip"]),
             notify=r.d(g["pflip"], a["latch"]), total=r.d(a["cpend"], g["pflip"]), t0=a["cpend"] or a["entry"], t1=g["pflip"] or g["seen"],
             missed=(g["vbl_pflip"]-g["vbl_armed"]-1) if g["pflip"] and g["armed"] else None, idle=g["idle"])
    if a["waited"] == 2:     # out-31 kernel fence: the GPU wait runs in NMXGPU's commit (worker); no plugin hand-off
        R["wake"] = R["handoff"] = None
    R["kf"] = a["waited"] == 2
    rows.append(R)
print("kernel-fence frames (waited 2)", sum(1 for x in rows if x["kf"]), "of", len(rows))
print("frames joined", len(rows), "seq", rows[0]["seq"], "-", rows[-1]["seq"], "span s", (rows[-1]["t0"]-rows[0]["t0"])/1e9)
for k in ["gpu","wake","handoff","pipe","worker","scanout","notify","total"]:
    xs=[x[k] for x in rows if x[k] is not None]
    print(f"{k:8} p50 {r.pct(xs,.5):7.2f} p90 {r.pct(xs,.9):7.2f} p99 {r.pct(xs,.99):7.2f} p999 {r.pct(xs,.999):7.2f} max {max(xs):7.2f}")
late=[x for x in rows if (x["total"] or 0) > 2*P or (x["missed"] or 0)>0]
vlate=[x for x in rows if (x["total"] or 0) > 3*P]
print("late (>2 periods or missed)", len(late), "very late (>3 periods)", len(vlate))
bl=collections.Counter()
for x in late:
    c={k:x[k] for k in ["gpu","wake","handoff","pipe","worker","scanout","notify"] if x[k] is not None}
    bl[max(c,key=c.get)]+=1
print("blame", dict(bl))
print("worker>4ms", sum(1 for x in rows if (x["worker"] or 0)>4), "handoff>4ms", sum(1 for x in rows if (x["handoff"] or 0)>4), "wake>4ms", sum(1 for x in rows if (x["wake"] or 0)>4))
gaps=[(rows[i+1]["t1"]-rows[i]["t1"])/1e6 for i in range(len(rows)-1) if rows[i]["t1"] and rows[i+1]["t1"]]
gaps.sort(); print("flip-to-flip gap p50 %.2f p99 %.2f max %.2f; >50ms %d" % (gaps[len(gaps)//2], gaps[int(.99*len(gaps))], gaps[-1], sum(1 for g in gaps if g>50)))
sv=list(st.values()); print("stall events >=1ms seen", len(sv), collections.Counter(x["kind"] for x in sv))
print("stall pids", collections.Counter((x["kind"],x["pid"]) for x in sv).most_common(8))
over=[(x["seq"],s["kind"],s["ms"]) for x in late for s in sv if x["t1"] and s["t0"]<x["t1"] and s["t1"]>x["t0"]]
print("late frames overlapping stalls", len(over), over[:10])
for x in sorted(vlate,key=lambda x:-x["total"])[:8]:
    print("  vlate", x["seq"], {k:round(x[k],2) for k in ["total","gpu","wake","handoff","worker","scanout","notify"] if x[k] is not None}, "missed", x["missed"])
print("idle flags", collections.Counter(x["idle"] for x in rows))
for l in ("flips","vbl_timer","ips","psr","out31"): print(last.get(l))
for l in last.get("stall",[]): print(l)
