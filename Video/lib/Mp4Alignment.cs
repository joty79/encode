using System;
using System.IO;
using System.Collections.Generic;
using System.Globalization;

namespace EncodeRepair {
    public sealed class AlignmentPlan {
        public string Status = "Unsupported";
        public string Reason = "No characterized alignment failure found.";
        public long Boundary, Shift, Length;
        public int VideoPackets, OriginalBadPackets, RemainingBadPackets;
        public double FirstBadPts, LastBadPts;
    }
    public static class Mp4Alignment {
        private sealed class Packet { public long Pos; public int Size; public double Pts; }
        private static uint U32(byte[] b, int o) {
            return ((uint)b[o] << 24) | ((uint)b[o+1] << 16) | ((uint)b[o+2] << 8) | b[o+3];
        }
        private static byte[] Read(FileStream f, long pos, int length) {
            byte[] b = new byte[length]; f.Position = pos; int done = 0;
            while (done < length) { int n = f.Read(b,done,length-done); if(n==0) throw new EndOfStreamException(); done+=n; }
            return b;
        }
        private static bool Equal(FileStream f, long a, long b, long length) {
            for(long o=0;o<length;o+=65536) {
                int n=(int)Math.Min(65536,length-o);
                byte[] x=Read(f,a+o,n), y=Read(f,b+o,n);
                for(int i=0;i<n;i++) if(x[i]!=y[i]) return false;
            }
            return true;
        }
        private static bool Valid(FileStream f, long pos, int size) {
            if(pos<0 || size<5 || size>64*1024*1024 || pos>f.Length-size) return false;
            byte[] b=Read(f,pos,size); int o=0; bool picture=false;
            while(o<size) {
                if(size-o<5) return false;
                uint n=U32(b,o); int type=b[o+4]&31;
                if(n<1 || n>(uint)(size-o-4) || type<1 || type>23 || (b[o+4]&128)!=0) return false;
                if(type>=1 && type<=5) picture=true;
                o+=4+(int)n;
            }
            return o==size && picture;
        }
        private static List<Packet> Parse(string text) {
            var packets=new List<Packet>();
            using(var reader=new StringReader(text)) {
                string line;
                while((line=reader.ReadLine())!=null) {
                    if(line.Length==0) continue;
                    var p=new Packet(); bool pos=false,size=false,pts=false;
                    foreach(string field in line.Split('|')) {
                        string[] kv=field.Split('='); if(kv.Length!=2) continue;
                        if(kv[0]=="pos") pos=long.TryParse(kv[1],out p.Pos);
                        if(kv[0]=="size") size=int.TryParse(kv[1],out p.Size);
                        if(kv[0]=="pts_time") pts=double.TryParse(kv[1],NumberStyles.Float,CultureInfo.InvariantCulture,out p.Pts);
                    }
                    if(!pos || !size || !pts || p.Pos<0 || p.Size<1) throw new InvalidDataException("Incomplete packet index.");
                    packets.Add(p);
                }
            }
            if(packets.Count<10) throw new InvalidDataException("Insufficient video packets.");
            packets.Sort((a,b)=>a.Pos.CompareTo(b.Pos));
            return packets;
        }
        public static AlignmentPlan Analyze(string path,string packetText) {
            var plan=new AlignmentPlan(); var packets=Parse(packetText); plan.VideoPackets=packets.Count;
            using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                plan.Length=f.Length; long mdatStart=-1,mdatEnd=-1,moov=-1,moovSize=0,at=0;
                while(at<f.Length) {
                    if(f.Length-at<8) { plan.Reason="Incomplete top-level atom.";return plan; }
                    byte[] h=Read(f,at,8); long size=U32(h,0); int header=8;
                    string type=System.Text.Encoding.ASCII.GetString(h,4,4);
                    if(size==1) {
                        if(f.Length-at<16) return plan;
                        byte[] ex=Read(f,at+8,8); ulong extended=((ulong)U32(ex,0)<<32)|U32(ex,4);
                        if(extended>long.MaxValue) return plan; size=(long)extended;header=16;
                    }
                    if(size==0) size=f.Length-at;
                    if(size<header || size>f.Length-at) { plan.Reason="Atom extends outside file.";return plan; }
                    if(type=="mdat") { if(mdatStart>=0) return plan;mdatStart=at+header;mdatEnd=at+size; }
                    if(type=="moov") { if(moov>=0) return plan;moov=at;moovSize=size; }
                    at+=size;
                }
                if(mdatStart<0 || moov<mdatEnd || moov+moovSize!=f.Length || moovSize>64*1024*1024) {
                    plan.Reason="Alignment recovery requires a single mdat and final bounded moov.";return plan;
                }
                foreach(var p in packets) {
                    if(p.Pos<mdatStart || p.Pos>mdatEnd-p.Size) {plan.Reason="Index points outside mdat.";return plan;}
                    if(!Valid(f,p.Pos,p.Size)) {
                        if(plan.OriginalBadPackets==0) plan.Boundary=p.Pos;
                        plan.OriginalBadPackets++;
                    }
                }
                if(plan.OriginalBadPackets==0) {plan.Status="NoPacketDamage";plan.Reason="All indexed H.264 packets structurally valid.";return plan;}
                // Search the mdat for a byte-identical duplicate of the final
                // index. A stray ASCII 'moov' is insufficient evidence.
                byte[] marker=Read(f,moov,8); var candidates=new List<long>();
                const int block=1024*1024;
                for(long start=mdatStart;start<mdatEnd;start+=block) {
                    int count=(int)Math.Min(block+7,mdatEnd-start); byte[] buf=Read(f,start,count);
                    for(int i=0;i+8<=count;i++) {
                        if(i>=block) break;
                        bool match=true;for(int j=0;j<8;j++) if(buf[i+j]!=marker[j]) {match=false;break;}
                        if(!match) continue;
                        long found=start+i;
                        if(found+moovSize<=moov && Equal(f,found,moov,moovSize)) candidates.Add(found);
                    }
                }
                if(candidates.Count!=1) {plan.Reason="No unique identical embedded moov; byte shift is unproven.";return plan;}
                plan.Shift=moov-candidates[0];
                if(plan.Shift<=0 || plan.Boundary<mdatStart || plan.Boundary+plan.Shift>=mdatEnd) return plan;
                bool ended=false; int recovered=0;
                foreach(var p in packets) {
                    long mapped=p.Pos+p.Size<=plan.Boundary ? p.Pos : p.Pos>=plan.Boundary+plan.Shift ? p.Pos-plan.Shift : -1;
                    bool good=mapped>=mdatStart && mapped+p.Size<=candidates[0] && Valid(f,mapped,p.Size);
                    if(!good) {
                        if(ended) {plan.Reason="Mapped damage is not one bounded contiguous interval.";return plan;}
                        if(plan.RemainingBadPackets==0) plan.FirstBadPts=p.Pts;
                        plan.LastBadPts=p.Pts;plan.RemainingBadPackets++;
                    } else if(plan.RemainingBadPackets>0) {ended=true;recovered++;}
                }
                if(plan.RemainingBadPackets==0 || !ended || recovered<10 ||
                   plan.LastBadPts-plan.FirstBadPts>30 || plan.LastBadPts<plan.FirstBadPts ||
                   plan.RemainingBadPackets>=plan.OriginalBadPackets/2) {
                    plan.Reason="Insufficient improvement or missing interval exceeds supported 30 seconds.";return plan;
                }
                plan.Status="RecoverableShift";
                plan.Reason="Unique identical index plus whole-file H.264 validation proves a bounded byte realignment candidate; audio and decode still require verification.";
                return plan;
            }
        }
        private static void Copy(FileStream src,FileStream dst,long start,long length) {
            src.Position=start;byte[] buffer=new byte[1024*1024];
            while(length>0) {int n=src.Read(buffer,0,(int)Math.Min(length,buffer.Length));if(n==0)throw new EndOfStreamException();dst.Write(buffer,0,n);length-=n;}
        }
        public static void Restore(string source,string output,AlignmentPlan plan) {
            if(plan.Status!="RecoverableShift") throw new InvalidOperationException("No accepted alignment plan.");
            using(var src=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                if(src.Length!=plan.Length) throw new IOException("Source changed since analysis.");
                using(var dst=new FileStream(output,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                    Copy(src,dst,0,plan.Boundary);
                    byte[] zeros=new byte[1024*1024];long left=plan.Shift;
                    while(left>0) {int n=(int)Math.Min(left,zeros.Length);dst.Write(zeros,0,n);left-=n;}
                    Copy(src,dst,plan.Boundary,plan.Length-plan.Shift-plan.Boundary);
                    if(dst.Length!=plan.Length) throw new IOException("Reconstruction length mismatch.");
                }
            }
        }
    }
}
