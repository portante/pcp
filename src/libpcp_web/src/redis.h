/*
 * Copyright (c) 2017-2020 Red Hat.
 * Copyright (c) 2009-2011, Salvatore Sanfilippo <antirez at gmail dot com>
 * Copyright (c) 2009-2014, Pieter Noordhuis <pcnoordhuis at gmail dot com>
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   * Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *   * Neither the name of Redis nor the names of its contributors may be used
 *     to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */
#ifndef SERIES_REDIS_H
#define SERIES_REDIS_H

#include "sds.h"
#include <stdarg.h>
#include <stdint.h>
#include <sys/time.h>

struct dict;
struct ssl_st;
struct redisContext;
struct redisAsyncContext;

#define REDIS_ERR -1
#define REDIS_OK   0

/*
 * When an error occurs, the err flag in a context is set to hold the type
 * of error that occurred.  REDIS_ERR_IO means there was an I/O error and
 * you should use the "errno" variable to find out what is wrong.
 * For other values, the "errstr" field will hold a description.
 */
#define REDIS_ERR_IO		1 /* Error in read or write */
#define REDIS_ERR_EOF		3 /* End of file */
#define REDIS_ERR_PROTOCOL	4 /* Protocol error */
#define REDIS_ERR_OOM		5 /* Out of memory */
#define REDIS_ERR_TIMEOUT	6 /* Timed out */
#define REDIS_ERR_OTHER		2 /* Everything else... */

/*
 * Several exact server error strings for fine-tuning behaviour.
 */
#define REDIS_ENOSCRIPT		"NOSCRIPT No matching script. Please use EVAL."
#define REDIS_ENOCLUSTER	"ERR This instance has cluster support disabled"
#define REDIS_ESTREAMXADD	"ERR The ID specified in XADD is equal or smaller than the target stream top item"

/*
 * Redis protocol reply types
 */
typedef enum redisReplyType {
    REDIS_REPLY_STRING		= 1,
    REDIS_REPLY_ARRAY		= 2,
    REDIS_REPLY_INTEGER		= 3,
    REDIS_REPLY_NIL		= 4,
    REDIS_REPLY_STATUS		= 5,
    REDIS_REPLY_ERROR		= 6,
    REDIS_REPLY_DOUBLE		= 7,
    REDIS_REPLY_BOOL		= 8,
    REDIS_REPLY_VERB		= 9,
    REDIS_REPLY_MAP		= 9,
    REDIS_REPLY_SET		= 10,
    REDIS_REPLY_ATTR		= 11,
    REDIS_REPLY_PUSH		= 12,
    REDIS_REPLY_BIGNUM		= 13,
    REDIS_REPLY_UNKNOWN		= -1
} redisReplyType;

#define REDIS_READER_MAX_BUF (1024*16)  /* Default max unused reader buffer. */

typedef struct redisReadTask {
    enum redisReplyType	type;      /* REDIS_REPLY_* type of this task */
    int			elements;  /* number of elements in multibulk container */
    int			idx;       /* index in parent (array) object */
    void		*obj;      /* holds user-generated value for a read task */
    struct redisReadTask *parent;  /* parent task */
    void		*privdata; /* user-settable arbitrary field */
} redisReadTask;

typedef struct redisReplyObjectFunctions {
    void *(*createString)(const redisReadTask*, char*, size_t);
    void *(*createArray)(const redisReadTask*, int);
    void *(*createInteger)(const redisReadTask*, long long);
    void *(*createDouble)(const redisReadTask*, double, char*, size_t);
    void *(*createNil)(const redisReadTask*);
    void *(*createBool)(const redisReadTask*, int);
    void (*freeObject)(void*);
} redisReplyObjectFunctions;

typedef struct redisReader {
    int			err;       /* Error flags, 0 when there is no error */
    char		errstr[128]; /* string representation of error */

    sds			buf;       /* Read buffer */
    size_t		pos;       /* Buffer cursor */
    size_t		len;       /* Buffer length */
    size_t		maxbuf;    /* Max length of unused buffer */

    redisReadTask	rstack[9];
    int			ridx;      /* Index of current read task */
    void		*reply;    /* Temporary reply pointer */

    redisReplyObjectFunctions *fn;
    void		*privdata;
} redisReader;

/* Public API for the protocol parser. */
redisReader *redisReaderCreateWithFunctions(redisReplyObjectFunctions *fn);
void redisReaderFree(redisReader *r);
int redisReaderFeed(redisReader *r, const char *buf, size_t len);
int redisReaderGetReply(redisReader *r, void **reply);

#define redisReaderSetPrivdata(_r, _p) (int)(((redisReader*)(_r))->privdata = (_p))
#define redisReaderGetObject(_r) (((redisReader*)(_r))->reply)
#define redisReaderGetError(_r) (((redisReader*)(_r))->errstr)

/* Connection type can be blocking or non-blocking and is set in the
 * least significant bit of the flags field in redisContext. */
#define REDIS_BLOCK		0x1

/* Connection may be disconnected before being free'd. The second bit
 * in the flags field is set when the context is connected. */
#define REDIS_CONNECTED		0x2

/* The async API might try to disconnect cleanly and flush the output
 * buffer and read all subsequent replies before disconnecting.
 * This flag means no new commands can come in and the connection
 * should be terminated once all replies have been read. */
#define REDIS_DISCONNECTING	0x4

/* Flag specific to the async API which means that the context should be clean
 * up as soon as possible. */
#define REDIS_FREEING		0x8

/* Flag that is set when an async callback is executed. */
#define REDIS_IN_CALLBACK	0x10

/* Flag that is set when the async context has one or more subscriptions. */
#define REDIS_SUBSCRIBED	0x20

/* Flag that is set when monitor mode is active */
#define REDIS_MONITORING	0x40

/* Flag that is set when we should set SO_REUSEADDR before calling bind() */
#define REDIS_REUSEADDR		0x80

/* Flag that is set when this connection is done through SSL */
#define REDIS_SSL		0x100

/* Flag that indicates the context should not be freed upon an error */
#define REDIS_NO_AUTO_FREE	0x200

#define REDIS_KEEPALIVE_INTERVAL 15 /* seconds */

/* number of times we retry to connect in the case of EADDRNOTAVAIL and
 * SO_REUSEADDR is being used. */
#define REDIS_CONNECT_RETRIES  10

/* This is the reply object returned by redisCommand() */
typedef struct redisReply {
    enum redisReplyType	type;       /* REDIS_REPLY_* type of this response */
    long long		integer;    /* value for type REDIS_REPLY_INTEGER */
    double		dval;       /* value for type REDIS_REPLY_DOUBLE */
    size_t		len;        /* length of string */
    char		*str;       /* used for both REDIS_REPLY_{ERROR,STRING} */
    size_t		elements;   /* elements count for REDIS_REPLY_ARRAY */
    struct redisReply	**element;  /* elements vector for REDIS_REPLY_ARRAY */
} redisReply;

extern redisReader *redisReaderCreate(void);

extern void freeReplyObject(void *);

extern const char *redis_reply_type(redisReply *);

enum redisConnectionType {
    REDIS_CONN_TCP,
    REDIS_CONN_UNIX,
    REDIS_CONN_USERFD
};

#define REDIS_OPT_NONBLOCK	0x01
#define REDIS_OPT_REUSEADDR	0x02

/**
 * Don't automatically free the async object on a connection failure,
 * or other implicit conditions. Only free on an explicit call to disconnect() or free()
 */
#define REDIS_OPT_NOAUTOFREE	0x04

/* In Unix systems a file descriptor is a regular signed int, with -1
 * representing an invalid descriptor. In Windows it is a SOCKET
 * (32- or 64-bit unsigned integer depending on the architecture), where
 * all bits set (~0) is INVALID_SOCKET.  */
#ifndef _WIN32
typedef int redisFD;
#define REDIS_INVALID_FD -1
#else
#ifdef _WIN64
typedef unsigned long long redisFD; /* SOCKET = 64-bit UINT_PTR */
#else
typedef unsigned long redisFD;      /* SOCKET = 32-bit UINT_PTR */
#endif
#define REDIS_INVALID_FD ((redisFD)(~0)) /* INVALID_SOCKET */
#endif

typedef struct redisOptions {
    int			type;		/* the type of connection to use. */
    int			options;	/* bit field of REDIS_OPT_xxx */
    const struct timeval *timeout;	/* timeout value. NULL for no timeout */
    union {
        /** use this field for TCP/IP connections */
        struct {
            const char	*source_addr;
            const char	*ip;
            int		port;
        } tcp;
        /** use this field for Unix domain sockets */
        const char	*unix_socket;
        /** use this field for an already-open file descriptor */
        redisFD		fd;
    } endpoint;
} redisOptions;

#define REDIS_OPTIONS_SET_TCP(opts, ip_, port_) \
    (opts)->type = REDIS_CONN_TCP; \
    (opts)->endpoint.tcp.ip = ip_; \
    (opts)->endpoint.tcp.port = port_;

#define REDIS_OPTIONS_SET_UNIX(opts, path) \
    (opts)->type = REDIS_CONN_UNIX;        \
    (opts)->endpoint.unix_socket = path;

typedef struct redisContextFuncs {
    void (*free_privdata)(void *);
    void (*async_read)(struct redisAsyncContext *);
    void (*async_write)(struct redisAsyncContext *);
    int (*read)(struct redisContext *, char *, size_t);
    int (*write)(struct redisContext *);
} redisContextFuncs;

/* Context for a connection to Redis */
typedef struct redisContext {
    const redisContextFuncs *funcs;
    int			err;
    char		errstr[128]; /* string representation of error */
    int			fd;
    int			flags;
    char		*obuf;       /* Write buffer */
    redisReader		*reader;     /* Protocol reader */

    enum redisConnectionType connection_type;
    struct timeval	*timeout;

    struct {
        char		*host;
        char		*source_addr;
        int		port;
    } tcp;

    struct {
        char		*path;
    } unix_sock;

    /* For non-blocking connect */
    struct sockaddr	*saddr;
    size_t		addrlen;

    /* Additional private data for extensions like SSL */
    void		*privdata;
} redisContext;

/* figure out and reduce this this set of functions - async */
extern redisContext *redisConnectWithOptions(const redisOptions *);
extern redisContext *redisConnect(const char *, int);
extern redisContext *redisConnectWithTimeout(const char *, int, const struct timeval);
extern redisContext *redisConnectNonBlock(const char *, int);
extern redisContext *redisConnectBindNonBlock(const char *, int,
                                       const char *);
extern redisContext *redisConnectBindNonBlockWithReuse(const char *, int, const char *);
extern redisContext *redisConnectUnix(const char *);
extern redisContext *redisConnectUnixWithTimeout(const char *, const struct timeval);
extern redisContext *redisConnectUnixNonBlock(const char *);
extern redisContext *redisConnectFd(redisFD);

/*
 * Secure the connection using SSL.
 * This should be done before any command is executed on the connection.
 */
extern int redisSecureConnection(redisContext *,
		const char *, const char *, const char *, const char *);
/**
 * Initiate SSL/TLS negotiation on a provided context.
 */
extern int redisInitiateSSL(redisContext *, struct ssl_st *);

/*
 * Reconnect the given context using the saved information.
 *
 * This re-uses the exact same connect options as in the initial connection.
 * host, ip (or path), timeout and bind address are reused,
 * flags are used unmodified from the existing context.
 *
 * Returns REDIS_OK on successful connect or REDIS_ERR otherwise.
 */
extern int redisReconnect(redisContext *);

extern int redisSetTimeout(redisContext *, const struct timeval);
extern void redisFree(redisContext *);
extern int redisBufferRead(redisContext *);
extern int redisBufferWrite(redisContext *, int *);

/* internal error handling interfaces */
#define __redis_strerror_r(errno, buf, len) pmErrStr_r(-(errno), (buf), (len))
extern void __redisSetError(redisContext *, int, const char *);

/*
 * In a blocking context, this function first checks if there are unconsumed
 * replies to return and returns one if so. Otherwise, it flushes the output
 * buffer to the socket and reads until it has a reply. In a non-blocking
 * context, it will return unconsumed replies until there are no more.
 */
extern int redisGetReply(redisContext *, void **);
extern int redisGetReplyFromReader(redisContext *, void **);

typedef void (redisAsyncCallBack)(struct redisAsyncContext *,
				  struct redisReply *, const sds, void *);
typedef struct redisCallBack {
    struct redisCallBack	*next; /* simple singly linked list */
    redisAsyncCallBack		*func;
    unsigned int		pending_subs;
    sds				command; /* copy of original command */
    void			*privdata;
} redisCallBack;

/* List of callbacks for Redis replies */
typedef struct redisCallBackList {
    redisCallBack		*head;
    redisCallBack		*tail;
} redisCallBackList;

/* Connection callback prototypes */
typedef void (redisDisconnectCallBack)(const struct redisAsyncContext *, int);
typedef void (redisConnectCallBack)(const struct redisAsyncContext *, int);

/* Context for an async connection to Redis */
typedef struct redisAsyncContext {
    /* Hold the regular context, so it can be realloc'ed. */
    redisContext		c;

    int				err;
    char			*errstr;

    void			*data;

    struct {
        void			*data;
        /* Hooks that are called when the library expects to start
         * reading/writing. These functions should be idempotent. */
        void (*addRead)(void *);
        void (*delRead)(void *);
        void (*addWrite)(void *);
        void (*delWrite)(void *);
        void (*cleanup)(void *);
	void (*scheduleTimer)(void *, struct timeval);
    } ev;

    /* Called when either the connection is terminated due to an error or per
     * user request. The status is set accordingly (REDIS_OK, REDIS_ERR). */
    redisDisconnectCallBack	*onDisconnect;

    /* Called when the first write event was received. */
    redisConnectCallBack 	*onConnect;

    /* Regular command callbacks */
    redisCallBackList		replies;

    /* Subscription callbacks */
    struct {
	redisCallBackList	invalid;
	struct dict		*channels;
	struct dict		*patterns;
    } sub;
} redisAsyncContext;

extern redisAsyncContext *redisAsyncConnect(const char *, int);
extern redisAsyncContext *redisAsyncConnectBind(const char *, int, const char *);
extern redisAsyncContext *redisAsyncConnectBindWithReuse(const char *, int, const char *);
extern redisAsyncContext *redisAsyncConnectUnix(const char *);
extern redisAsyncContext *redisAsyncConnectWithOptions(const redisOptions *);

extern int redisAsyncSetConnectCallBack(redisAsyncContext *, redisConnectCallBack *);
extern int redisAsyncSetDisconnectCallBack(redisAsyncContext *, redisDisconnectCallBack *);
extern int redisAsyncEnableKeepAlive(redisAsyncContext *);
extern void redisAsyncSetTimeout(redisAsyncContext *, struct timeval);
extern void redisAsyncDisconnect(redisAsyncContext *);
extern void redisAsyncFree(redisAsyncContext *);

/* Handle read/write events */
extern void redisAsyncHandleRead(redisAsyncContext *);
extern void redisAsyncHandleWrite(redisAsyncContext *);
extern int redisAsyncFormattedCommand(redisAsyncContext *, redisAsyncCallBack *, const sds, void *);

#define REDIS_EV_ADD_READ(ctx) do { \
        refreshTimeout(ctx); if ((ctx)->ev.addRead) (ctx)->ev.addRead((ctx)->ev.data); \
    } while(0)
#define REDIS_EV_DEL_READ(ctx) do { \
        if ((ctx)->ev.delRead) (ctx)->ev.delRead((ctx)->ev.data); \
    } while(0)
#define REDIS_EV_ADD_WRITE(ctx) do { \
        refreshTimeout(ctx); if ((ctx)->ev.addWrite) (ctx)->ev.addWrite((ctx)->ev.data); \
    } while(0)
#define REDIS_EV_DEL_WRITE(ctx) do { \
        if ((ctx)->ev.delWrite) (ctx)->ev.delWrite((ctx)->ev.data); \
    } while(0)
#define REDIS_EV_CLEANUP(ctx) do { \
        if ((ctx)->ev.cleanup) { (ctx)->ev.cleanup((ctx)->ev.data); (ctx)->ev.data = NULL; } \
    } while(0);

static inline void refreshTimeout(redisAsyncContext *ctx) {
    if (ctx->c.timeout && ctx->ev.scheduleTimer &&
        (ctx->c.timeout->tv_sec || ctx->c.timeout->tv_usec)) {
        ctx->ev.scheduleTimer(ctx->ev.data, *ctx->c.timeout);
    }
}

extern void __redisAsyncDisconnect(redisAsyncContext *);
extern void redisProcessCallBacks(redisAsyncContext *);

#endif /* SERIES_REDIS_H */
