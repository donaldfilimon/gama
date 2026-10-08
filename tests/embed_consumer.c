/* Test-only strict linked C consumer: exact declarations, runtime and frozen bytes. */
#include "GamaEmbed.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
static int checks;
#define CHECK(x) do { ++checks; if (!(x)) { fprintf(stderr, "C ABI assertion %d at line %d: %s\n", checks, __LINE__, #x); exit(1); } } while (0)
static void golden(const uint8_t *bytes, int32_t n, const char *path) {
    uint8_t expected[111]; FILE *f = fopen(path,"rb"); CHECK(f != NULL);
    size_t count = fread(expected,1,sizeof expected,f); CHECK(!ferror(f)); CHECK(fclose(f)==0);
    CHECK(count==110 && n==110 && bytes!=NULL); CHECK(memcmp(bytes,expected,count)==0);
}
int main(void) {
    int32_t (*version)(void) = gama_embed_v1_abi_version;
    GamaEmbedContext (*create)(int32_t,int32_t) = gama_embed_v1_context_create;
    void (*destroy)(GamaEmbedContext) = gama_embed_v1_context_destroy;
    int32_t (*resize)(GamaEmbedContext,int32_t,int32_t) = gama_embed_v1_resize;
    int32_t (*key)(GamaEmbedContext,int32_t,int32_t,int32_t,int32_t) = gama_embed_v1_key;
    int32_t (*pointer)(GamaEmbedContext,int32_t,int32_t,int32_t) = gama_embed_v1_pointer;
    int32_t (*needs)(GamaEmbedContext) = gama_embed_v1_needs_frame;
    const uint8_t *(*frame)(GamaEmbedContext,int32_t*) = gama_embed_v1_frame;
    CHECK(version()==1); CHECK(GAMA_EMBED_ERR_OUT_OF_MEMORY==-4);
    CHECK(key(NULL,999,-1,-1,-1)==-1); CHECK(resize(NULL,0,0)==-1);
    CHECK(pointer(NULL,0,0,1)==-1); CHECK(needs(NULL)==-1);
    int32_t n=99; CHECK(frame(NULL,&n)==NULL && n==-1); CHECK(frame(NULL,NULL)==NULL); destroy(NULL);
    GamaEmbedContext ctx=create(24,6); CHECK(ctx!=NULL); CHECK(needs(ctx)==1);
    CHECK(key(ctx,5,-1,0,0)==0); CHECK(pointer(ctx,1,1,1)==0);
    const uint8_t *p=frame(ctx,&n); golden(p,n,"tests/parity/swift-baseline/c-embed-initial.gama");
    uint8_t saved[110]; memcpy(saved,p,sizeof saved);
    CHECK(needs(ctx)==0); CHECK(frame(ctx,&n)==NULL && n==0);
    CHECK(key(ctx,5,-1,INT_MIN,INT_MIN)==0);
    p=frame(ctx,&n); golden(p,n,"tests/parity/swift-baseline/c-embed-increment.gama");
    CHECK(saved[56]=='0' && p[56]=='1'); CHECK(needs(ctx)==0); CHECK(frame(ctx,&n)==NULL && n==0);
    const int32_t invalid[]={-1,0xd800,0xdfff,0x110000,INT_MAX};
    for(size_t i=0;i<sizeof invalid/sizeof invalid[0];++i) CHECK(key(ctx,0,invalid[i],0,0)==-2);
    const int32_t codes[]={1,2,3,4,5,6,7,8,9,10,11,12,13,100,101,102,103,104,105,106,107,108,109,110,111,112};
    for(size_t i=0;i<sizeof codes/sizeof codes[0];++i) CHECK(key(ctx,codes[i],-1,-7,-9)==0);
    CHECK(key(ctx,14,0,0,0)==-2); CHECK(key(ctx,99,0,0,0)==-2); CHECK(key(ctx,113,0,0,0)==-2);
    CHECK(key(ctx,0,0,0,0)==0); CHECK(key(ctx,0,0xffff,0,0)==0); CHECK(key(ctx,0,0x10ffff,0,0)==0);
    CHECK(resize(ctx,INT_MAX,INT_MAX)==0); p=frame(ctx,&n); CHECK(p!=NULL && n==20);
    for(int i=8;i<20;++i) CHECK(p[i]==0);
    CHECK(needs(ctx)==0); CHECK(frame(ctx,&n)==NULL && n==0);
    CHECK(resize(ctx,24,6)==0); CHECK(frame(ctx,NULL)!=NULL); CHECK(needs(ctx)==0);
    CHECK(frame(ctx,&n)==NULL && n==0);
    destroy(ctx);
    ctx=create(24,6); CHECK(ctx!=NULL); CHECK(frame(ctx,NULL)!=NULL);
    CHECK(pointer(ctx,-1,1,-1)==0 && needs(ctx)==0);
    CHECK(pointer(ctx,11,1,1)==0 && needs(ctx)==0);
    CHECK(pointer(ctx,1,0,1)==0 && needs(ctx)==0);
    CHECK(pointer(ctx,1,1,0)==0 && needs(ctx)==0);
    CHECK(pointer(ctx,10,1,INT_MIN)==0 && needs(ctx)==1);
    p=frame(ctx,&n); golden(p,n,"tests/parity/swift-baseline/c-embed-increment.gama");
    CHECK(key(ctx,0,' ',0,INT_MIN)==0 && needs(ctx)==1); CHECK(frame(ctx,NULL)!=NULL);
    CHECK(key(ctx,7,-1,-1,-1)==0 && needs(ctx)==1); CHECK(frame(ctx,NULL)!=NULL);
    CHECK(key(ctx,0,0x0130,0,-1)==0 && needs(ctx)==0);
    CHECK(resize(ctx,-1,0)==0); p=frame(ctx,&n); CHECK(p!=NULL && n>=20 && p[8]==1 && p[12]==1);
    destroy(ctx);
    fprintf(stderr,"All %d linked C ABI assertions passed\n",checks); return 0;
}
