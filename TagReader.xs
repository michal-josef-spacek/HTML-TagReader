/* vim: set sw=8 ts=8 si noet: */
/* read the following man pages: perlxs perlxstut perlguts perlcall  */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>

/* tags longer than TAGREADER_MAX_TAGLEN produce a warning about
* not terminated tags */
#define TAGREADER_MAX_TAGLEN 500
#define BUFFLEN 7000
#define TAGREADER_TAGTYPELEN 20

typedef struct trstuct{
	char *filename;
	int fileline;
	int tagline;
	char buffer[BUFFLEN + 1];
	char tagtype[TAGREADER_TAGTYPELEN + 1];
	FILE *fd;
} *HTML__TagReader;

/* start of a html tag (first char in the tag) */
static inline int is_start_of_tag(int ch){
	if (ch=='!' || ch=='/' || ch=='?' || isalpha(ch)){
		return(1);
	}
	return(0);
}

MODULE = HTML::TagReader	PACKAGE = HTML::TagReader	PREFIX = tr_	

HTML::TagReader 
tr_new(class, filename)
	SV *class
	SV *filename
CODE:
	int i;
	char *str;
	if (!SvPOK (filename)){
		croak("filename must be a string scalar");
	}    
	/* malloc and zero the struct */
        Newz(0, RETVAL, 1, struct trstuct );
	str=SvPV(filename,i);
	/* malloc */
        New(0, RETVAL->filename, i+1, char );
	strncpy(RETVAL->filename,str,i);
	/* put a zero at the end of the string, perl might not do it */
	*(RETVAL->filename + i )=(char)0;
	RETVAL->fd=fopen(str,"r");
	if (RETVAL->fd == NULL){
		croak("can not read file %s",str);
	}
	RETVAL->fileline=1;
	RETVAL->tagline=0;
OUTPUT:
	RETVAL

void
DESTROY(self)
	HTML::TagReader self
CODE:
	Safefree(self->filename);
	fclose(self->fd);
	Safefree(self);

void
tr_gettag(self,showerrors)
	HTML::TagReader self
	SV *showerrors
PREINIT:
	int bufpos;
	char ch;
	char chn;
	int state;
PPCODE:
        if (! self->fileline){
		croak("Object not initialized");
	}
	/* initialize */
	state=0;
	bufpos=0;
	ch=(char)0;
	chn=(char)0;
	self->tagline=self->fileline;
	/* find the next tag */
	while(state != 3 && (chn=fgetc(self->fd))!=EOF ){
		if (ch==0){ /* read one more character ahead so we have always 2 */
			ch=chn;
			continue;
		}
		if (bufpos > BUFFLEN - 2 || bufpos > TAGREADER_MAX_TAGLEN){
			if (SvTRUE(showerrors)){
				fprintf(stderr,"%s:%d: ERROR, tag not terminated or too long.\n",self->filename,self->tagline);
			}
			state=0;
			self->buffer[0]=(char)0; /* zero buffer*/
			bufpos=0;
		}
		if (ch=='\n') self->fileline++;
		if (ch=='\n'|| ch=='\r' || ch=='\t' || ch==' ') {
			ch=' ';
			if (chn=='\n'|| chn=='\r' || chn=='\t' || chn==' '){
				/* delete mupltiple spaces */
				ch=chn; /* shift next char */
				continue;
			}
		}
		switch (state) {
		/*---*/
			case 0:
			/* outside of tag and we start tag here*/
			if (ch=='<') {
				if (is_start_of_tag(chn)) {
					self->buffer[0]=(char)0;
					bufpos=0;
					/*line where tag starts*/
					self->tagline=self->fileline;
					self->buffer[bufpos]=ch;bufpos++;
					state=1;
				}else{
					if (SvTRUE(showerrors)){
						fprintf(stderr,"%s:%d: ERROR, single \'<\' should be written as &gt;\n",self->filename,self->fileline);
					}
				}
			}
			break;
		/*---*/
			case 1:
			self->buffer[bufpos]=ch;bufpos++;
			if (ch=='!' && chn=='-' && self->buffer[bufpos-2]=='<'){
				/* start of comment handling */
				state=30; 
			}
			if (ch=='>'){
				state=3; /* note the exit state is hardcoded
				          * as well in the while loop above */
				self->buffer[bufpos]=(char)0;bufpos++;
			}
			if(ch=='<'){
				/* the tag that we were reading was not terminated but instead we ge a new opening */
				if (SvTRUE(showerrors)){
					fprintf(stderr,"%s:%d: ERROR, \'>\' inside a tag should be written as &lt;\n",self->filename,self->tagline);
				}
				state=1;
				bufpos=0;
				self->buffer[bufpos]=ch;bufpos++;
				self->tagline=self->fileline;
			}
			break;
		/*---*/
			case 30: /*comment handling,
				*we have found "<!--", wait for
				*comment termination with "->" */
				if(ch=='-' && chn=='>'){
					/* done reading this comment tag 
					* just get the closing '>'*/
					state=31;
				}
			break;
		/*---*/
			case 31: 
				/* done reading this comment tag */
				state=0;
				self->buffer[0]=(char)0; /* zero buffer*/
				bufpos=0;
			break;
		/*---*/
			default:
				fprintf(stderr,"%s:%d: Programm Error, state = %d\n",self->filename,self->fileline,state);
				exit(1);
		}
		/* shift this and next char */
		ch=chn;
	}
	/* put back chn for the next round */
	if (chn!=EOF && ungetc(chn,self->fd)==EOF){
		fprintf(stderr,"%s:%d: ERROR, TagReader library can not ungetc \"%c\" before returning\n",self->filename,self->fileline,chn);
		exit(1);
	}
	/* terminate buffer*/
	if (state == 3){
		/* we have found a tag */
		if(GIMME == G_ARRAY){
			EXTEND(SP,2);
			XST_mPV(0,self->buffer);
			XST_mIV(1,self->tagline);
			XSRETURN(2);
		}else{
			EXTEND(SP,1);
			XST_mPV(0,self->buffer);
			XSRETURN(1);
		}
	}else{
		/* we are at the end of the file and no tag was found 
		 * return an empty list or string such that the user 
		 * will probably call destroy.
		 */
		 XSRETURN_EMPTY;
	}

void
tr_getbytoken(self,showerrors)
	HTML::TagReader self
	SV *showerrors
PREINIT:
	int bufpos;
	char ch;
	char chn; /* next character */
	int typepos;
	int typeposdone;
	int state;
PPCODE:
        if (! self->fileline){
		croak("Object not initialized");
	}
	/* initialize */
	state=0;
	bufpos=0;
	typeposdone=0;
	typepos=0;
	self->buffer[bufpos]=(char)0;
	self->tagline=self->fileline;
	self->tagtype[typepos]=(char)0;
	ch=(char)0;chn=(char)0;
	/* find the next tag */
	while(state != 3 && (chn=fgetc(self->fd))!=EOF ){
		if (ch==0){ /* read one more character ahead so we have always 2 */
			ch=chn;
			continue;
		}
		if (ch=='\n') self->fileline++;
		//printf("DBG ch%c chn%c state%d\n",ch ,chn,state);
		self->buffer[bufpos]=ch;bufpos++;
		switch (state) {
		/*---*/
			case 0:
			if (ch=='<'){
				if ( is_start_of_tag(chn)) { 
					state=1; /* we will be reading a tag */
				}else{
					state=2; /* we will be reading a text/paragraph */
					if (SvTRUE(showerrors)){
						fprintf(stderr,"%s:%d: ERROR, single \'<\' should be written as &gt;\n",self->filename,self->fileline);
					}
				}
			}else{
				state=2; /* we will be reading a text/paragraph */
			}
			break;
		/*---*/
			case 1:
			/* inside a tag. Wait for '>' */
			if (typeposdone==0 && typepos < TAGREADER_TAGTYPELEN -1 ){ 
				if (is_start_of_tag(ch)){
					self->tagtype[typepos]=tolower(ch);typepos++;
				}else{
					/* end of tag type e.g "<a " -> save only "a" in 
					*  tagtype array */
					self->tagtype[typepos]=(char)0;
					typeposdone=1; /* mark end */
				}
			}
			if (ch=='<' && SvTRUE(showerrors)) {
				fprintf(stderr,"%s:%d: ERROR, single \'<\' or tag starting at line %d not terminated\n",self->filename,self->fileline,self->tagline);
			}
			if (SvTRUE(showerrors) && bufpos > TAGREADER_MAX_TAGLEN){
				fprintf(stderr,"%s:%d: ERROR, tag not terminated or too long.\n",self->filename,self->tagline);
			}
			if (ch=='>') {
				/* done reading this tag */
				state=3;
			}
			if (ch=='!' && chn=='-' && bufpos > 1 && self->buffer[bufpos-2]=='<'){
				/* start of comment handling */
				state=30; 
				/* some comments are <!-----, but we want always
				* the same tagtype for all comments: */
				strcpy(&(self->tagtype[0]),"!--");
				typepos=3;
			}
			break;
		/*---*/
			case 2:
			/* inside a text. Wait for start of tag */
			if (ch=='<'){
				if ( is_start_of_tag(chn)) { /* first char */
					/* put the start of tag back, we want to
					* return only the text part */
					if (ungetc(chn,self->fd)==EOF){
						fprintf(stderr,"%s:%d: ERROR, TagReader library can not ungetc \"%c\"\n",self->filename,self->fileline,chn);
						exit(1);
					}
					chn=ch;
					bufpos--;
					state=3;
				}else{
					state=2; /* we will be reading a text/paragraph */
					if (SvTRUE(showerrors)){
						fprintf(stderr,"%s:%d: ERROR, single \'<\' should be written as &gt;\n",self->filename,self->fileline);
					}
				}
			}
			break;
		/*---*/
			case 30: /*comment handling,
				*we have found "<!--", wait for
				*comment termination with "->" */
				if(ch=='-' && chn=='>'){
					/* done reading this comment tag 
					* just get the closing '>'*/
					state=31;
				}
			break;
		/*---*/
			case 31: 
				/* done reading this comment tag */
				state=3;
			break;
		/*---*/
			default:
				fprintf(stderr,"%s:%d: Programm Error, state = %d\n",self->filename,self->fileline,state);
				exit(1);
		}
		/* shift this and next char */
		ch=chn;
		if (bufpos > BUFFLEN - 3){
			if (SvTRUE(showerrors)){
				fprintf(stderr,"%s:%d: ERROR, too long paragraph or tag.\n",self->filename,self->tagline);
			}
			state=3; /* jump out of here */
		}
	} /* end of while */
	if (chn==EOF){
		/* put the last char (ch) in the buffer */
		if (ch) {
			self->buffer[bufpos]=ch;bufpos++;
		}
	}else{
		/* put back chn for the next round */
		if (ungetc(chn,self->fd)==EOF){
			fprintf(stderr,"%s:%d: ERROR, TagReader library can not ungetc \"%c\" before returning\n",self->filename,self->fileline,chn);
			exit(1);
		}
	}
	/* terminate buffer*/
	self->buffer[bufpos]=(char)0; 
	self->tagtype[typepos]=(char)0;
	/* state == 3 is here or eof */
	if (bufpos>0){
		/* we have a tag or text and we return it */
		if(GIMME == G_ARRAY){
			EXTEND(SP,3);
			XST_mPV(0,self->buffer);
			XST_mPV(1,self->tagtype);
			XST_mIV(2,self->tagline);
			XSRETURN(3);
		}else{
			EXTEND(SP,1);
			XST_mPV(0,self->buffer);
			XSRETURN(1);
		}
	}else{
		/* we are at the end of the file and no tag was found 
		 * return an empty list or string such that the user 
		 * will probably call destroy.
		 */
		 XSRETURN_EMPTY;
	}

	/* end of file */
