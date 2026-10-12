#!/usr/bin/env python3
import json,pathlib,time
HERE=pathlib.Path(__file__).resolve().parent
p=HERE/'post-fix/hard-vs-baseline-15.jsonl'
rows=[json.loads(line) for line in p.read_text().splitlines()]
games=[x for x in rows if x.get('event')=='game' and x['winner']=='baselineHard']
N=15
windows=[]
for dr,dc in [(1,0),(0,1),(1,1),(1,-1)]:
 for r in range(N):
  for c in range(N):
   if 0<=r+4*dr<N and 0<=c+4*dc<N:windows.append(tuple((r+k*dr)*N+c+k*dc for k in range(5)))
def square(s):return (int(s[1:])-1)*N+ord(s[0])-65
def coord(i):return chr(65+i%N)+str(i//N+1)
def winning_moves(b,p):
 result=set()
 for w in windows:
  stones=0;empty=-1;blocked=False
  for i in w:
   cell=b[i]
   if cell==p:stones+=1
   elif cell==0:
    if empty!=-1:blocked=True;break
    empty=i
   else:blocked=True;break
  if not blocked and stones==4:result.add(empty)
 return result
def already_won(b,p):return any(all(b[i]==p for i in w) for w in windows)
def losing_reply(b,defender):
 attacker=3-defender
 wins=winning_moves(b,attacker)
 if wins:return {'reply':coord(min(wins)),'type':'immediate_win','continuations':[]}
 for j in range(N*N):
  if b[j]:continue
  b[j]=attacker
  nextwins=winning_moves(b,attacker)
  if len(nextwins)>=2 and not winning_moves(b,defender):
   b[j]=0
   return {'reply':coord(j),'type':'fork','continuations':[coord(k) for k in sorted(nextwins)]}
  b[j]=0
 return None
def audit_game(game):
 b=[0]*(N*N)
 for k,s in enumerate(game['openingMoves']):b[square(s)]=1+k%2
 findings=[]
 for d in game['decisions']:
  player=1 if d['side']=='Black' else 2
  selected=square(d['move'])
  if d['engine']=='current':
   own_before=winning_moves(b,player)
   other_before=winning_moves(b,3-player)
   b[selected]=player
   witness=None if already_won(b,player) else losing_reply(b,player)
   b[selected]=0
   if witness:
    safe=[]
    for alternative in range(N*N):
     if b[alternative]:continue
     b[alternative]=player
     if already_won(b,player) or losing_reply(b,player) is None:safe.append(coord(alternative))
     b[alternative]=0
    finding={'ply':d['ply'],'chosen':d['move'],'ownImmediateWinsBefore':[coord(k) for k in sorted(own_before)],'opponentImmediateWinsBefore':[coord(k) for k in sorted(other_before)],'witness':witness,'safeAlternatives':safe}
    findings.append(finding);print(finding,flush=True)
  b[selected]=player
 out={'opening':game['opening'],'hardSide':game['hardSide'],'plies':game['plies'],'winner':game['winner'],'history':game['openingMoves']+[d['move'] for d in game['decisions']],'independentAudit':'Full-board five-cell windows; checks immediate win and one-reply fork, excluding defender immediate counterwin.','tacticalFindings':findings,'avoidableImmediateOrForkBlunders':sum(bool(x['safeAlternatives']) for x in findings)}
 return out

audits=[audit_game(game) for game in games]
summary={'lossesAudited':len(audits),'avoidableImmediateOrForkBlunders':sum(x['avoidableImmediateOrForkBlunders'] for x in audits),'losses':audits}
p.parent.joinpath('baseline-loss-audit.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary),flush=True)
