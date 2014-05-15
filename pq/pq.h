/*
 *   See file COPYRIGHT for copying and redistribution conditions.
 */

#ifndef _PQ_H
#define _PQ_H

#include <sys/types.h>	/* off_t, mode_t */
#include <stddef.h>	/* size_t */

#include "ldm.h"        /* prod_class_t */
#include "prod_class.h"


/*
 * The functions below return ENOERR upon success.
 * Upon failure, the return something else :-).
 * (Usually, that something else will be the a system
 * error (errno.h), don't count on it making sense.)
 */
#ifndef ENOERR
#define ENOERR 0
#endif /*!ENOERR */

#define PQ_END		-1	/* at end of product-queue */
#define PQ_CORRUPT	-2	/* the product-queue is corrupt */
#define PQ_NOTFOUND	-3	/* no such data-product */

typedef struct pqueue pqueue; /* private, implemented in pq.c */
extern struct pqueue *pq;

typedef struct pqe_index pqe_index;

/* prototype for 4th arg to pq_sequence() */
typedef int pq_seqfunc(const prod_info *infop, const void *datap,
	void *xprod, size_t len,
	void *otherargs);

/*
 * Which direction the cursor moves in pq_sequence().
 */
typedef enum {
	TV_LT = -1,
	TV_EQ =  0,
	TV_GT =  1
} pq_match;

struct pqe_index {
	off_t offset;
	signaturet signature;
};

/*
 * pflags arg to pq_open() and pq_create()
 */
#define PQ_DEFAULT	0x00
#define PQ_NOCLOBBER	0x01	/* Don't destroy existing file on create */
#define PQ_READONLY	0x02	/* Default is read/write */
#define PQ_NOLOCK	0x04	/* Disable locking */
#define PQ_PRIVATE	0x08	/* mmap() the file MAP_PRIVATE, default MAP_SHARED */
#define PQ_NOGROW	0x10	/* If pq_create(), must have intialsz */
#define PQ_NOMAP	0x20	/* Use malloc/read/write/free instead of mmap() */
#define PQ_MAPRGNS	0x40	/* Map region by region, default whole file */
#define PQ_SPARSE       0x80    /* Created as sparse file, zero blocks unallocated */
/* N.B.: bits 0x1000 (and above) in use internally */

#define pqeOffset(pqe) ((pqe).offset)
#define pqeEqual(left, rght) (pqeOffset(left) == pqeOffset(rght))

#define PQE_NONE (_pqenone)
#define pqeIsNone(pqe) (pqeEqual(pqe, PQE_NONE))
#define PQUEUE_DUP (-2)	/* return value indicating attempt to insert
				duplicate product */
#define PQUEUE_BIG (-3)	/* return value indicating attempt to insert
				product that's too large */
#define PQUEUE_END PQ_END	/* return value indicating end of queue */

#ifdef __cplusplus
extern "C" {
#endif

extern const pqe_index _pqenone;

/**
 * Resets the random number generator.
 */
void
pq_reset_random(void);

/*
 * On success, the writer-counter of the created product-queue will be one.
 */
int
pq_create(const char *path, mode_t mode,
        int pflags,
        size_t align,
        off_t initialsz, /* initial allocation available */
        size_t nproducts, /* initial rl->nalloc, ... */
        pqueue **pqp);

/*
 * Arguments:
 *      path    Pathname of product-queue.
 *      pflags  File-open bit-flags.
 *      pqp     Memory location to receive pointer to product-queue structure.
 * Returns:
 *      0           Success. *pqp set.
 *      EACCESS     Permission denied. pflags doesn't contain PQ_READONLY and 
 *                  the product-queue is already open by the maximum number of
 *                  writers.
 *      PQ_CORRUPT  The  product-queue is internally inconsistent.
 *      else        Other <errno.h> error-code.
 */
int
pq_open(
    const char* const path,
    int               pflags,
    pqueue** const    pqp);

/*
 * On success, if the product-queue was open for writing, then its 
 * writer-counter will be decremented.
 *
 * Returns:
 *      0               Success.
 *      EOVERFLOW       Write-count of product queue was prematurely zero.
 *      !0              Other <errno.h> code.
 */
int
pq_close(pqueue *pq);

/*
 * Let the user find out the pagesize.
 */
int
pq_pagesize(const pqueue *pq);

/**
 * Returns the size of the data portion of a product-queue.
 *
 * @param[in] pq  Pointer to the product-queue object.
 * @return        The size, in bytes, of the data portion of the product-queue.
 */
size_t
pq_getDataSize(
    pqueue* const       pq);

/**
 * Returns an allocated region into which to write a data-product based on
 * data-product metadata.
 *
 * Arguments:
 *      pq              Pointer to the product-queue object.
 *      infop           Pointer to the data-product metadata object.
 *      ptrp            Pointer to the pointer to the region into which to 
 *                      write the data-product.  Set upon successful return.
 *      indexp          Pointer to the handle to identify the region.  Set
 *                      upon successful return. The client must call \c
 *                      pqe_insert() when all the data has been written or \c
 *                      pqe_discard() to abort the writing and release the
 *                      region.
 * Returns:
 *      0               Success.  "*ptrp" and "*indexp" are set.
 *      else            <errno.h> error code.
 */
int
pqe_new(pqueue *pq,
        const prod_info *infop,
        void **ptrp, pqe_index *indexp);

/**
 * Returns an allocated region into which to write an XDR-encoded data-product.
 *
 * This function is thread-compatible but not thread-safe.
 *
 * @param[in]  pq         Pointer to the product-queue.
 * @param[in]  size       Size of the XDR-encoded data-product in bytes --
 *                        including the data-product metadata.
 * @param[in]  signature  The data-product's MD5 checksum.
 * @param[out] ptrp       Pointer to the pointer to the region into which to
 *                        write the XDR-encoded data-product -- starting with
 *                        the data-product metadata. The client must begin
 *                        writing at \c *ptrp and not write more than \c size
 *                        bytes of data.
 * @param[out] indexp     Pointer to the handle to identify the region. The
 *                        client must call \c pqe_insert() when all the data has
 *                        been written or \c pqe_discard() to abort the writing
 *                        and release the region.
 * @retval     0          Success.  \c *ptrp and \c *indexp are set.
 * @retval     EINVAL     @code{pq == NULL || ptrp == NULL || indexp == NULL}. \c
 *                        log_add() called.
   @retval     EACCES     Product-queue is read-only. \c log_add() called.
 * @retval     PQUEUE_BIG Data-product is too large for product-queue. \c
 *                        log_add() called.
 * @retval     PQUEUE_DUP If a data-product with the same signature already
 *                        exists in the product-queue.
 * @return                <errno.h> error code. \c log_add() called.
 */
int
pqe_newDirect(
    pqueue* const     pq,
    const size_t      size,
    const signaturet  signature,
    char** const      ptrp,
    pqe_index* const  indexp);

/**
 * Discards a region obtained from \c pqe_new() or \c pqe_newWithNoInfo().
 *
 * Arguments:
 *      pq              Pointer to the product-queue.  Shall not be NULL.
 *      pqe_index       Pointer to the region-index set by "pqe_new()".  Shall
 *                      not be NULL.
 * Returns:
 *      0               Success.
 *      else            <errno.h> error code.
 */
int
pqe_discard(pqueue *pq, pqe_index index);

/*
 * LDM 4 convenience funct.
 * Change signature, Insert at rear of queue, send SIGCONT to process group
 */
int
pqe_xinsert(pqueue *pq, pqe_index index, const signaturet realsignature);

/*
 * Insert at rear of queue, send SIGCONT to process group
 */
int
pqe_insert(pqueue *pq, pqe_index index);

/*
 * Insert at rear of queue
 * (Don't signal process group.)
 *
 * Returns:
 *      ENOERR  Success.
 *      EINVAL  Invalid argument.
 *      PQUEUE_DUP      Product already exists in the queue.
 *      PQUEUE_BIG      Product is too large to insert in the queue.
 */
int
pq_insertNoSig(pqueue *pq, const product *prod);

/*
 * Insert at rear of queue, send SIGCONT to process group
 *
 * Returns:
 *      ENOERR          Success.
 *      EINVAL          Invalid argument.
 *      PQUEUE_DUP      Product already exists in the queue.
 *      PQUEUE_BIG      Product is too large to insert in the queue.
 */
int
pq_insert(pqueue *pq, const product *prod);

/*
 * Returns some useful, "highwater" statistics of a product-queue.  The
 * statistics are since the queue was created.
 *
 * Arguments:
 *      pq              Pointer to the product-queue.  Shall not be NULL.
 *      highwaterp      Pointer to the maxium number of bytes used in the
 *                      data portion of the product-queue.  Shall not be NULL.
 *                      Set upon successful return.
 *      maxproductsp    Pointer to the maximum number of data-products that the
 *                      product-queue has held since it was created.  Shall not
 *                      be NULL.  Set upon successful return.
 * Returns:
 *      0               Success.  "*highwaterp" and "*maxproductsp" are set.
 *      else            <errno.h> error code.
 */
int
pq_highwater(pqueue *pq, off_t *highwaterp, size_t *maxproductsp);

/*
 * Indicates if the product-queue is full (i.e., if a data-product has been
 * deleted in order to make room for another data-product).
 *
 * Arguments:
 *      pq              Pointer to the product-queue structure.  Shall not be
 *                      NULL.
 *      isFull          Pointer to the indicator of whether or not the queue
 *                      is full.  Shall not be NULL.  Set upon successful
 *                      return.  "*isfull" will be non-zero if and only if the
 *                      product-queue is full.
 * Returns:
 *      0               Success.  "*isFull" is set.
 *      else            <errno.h> error code.
 */
int pq_isFull(
    pqueue* const       pq,
    int* const          isFull);

/*
 * Returns the time of the most-recent insertion of a data-product.
 *
 * Arguments:
 *      pq              Pointer to the product-queue structure.  Shall not be
 *                      NULL.
 *      mostRecent      Pointer to the time of the most-recent insertion of a
 *                      data-product.  Upon successful return, "*mostRecent"
 *                      shall be TS_NONE if such a time doesn't exist (because
 *                      the queue is empty, for example).
 * Returns:
 *      0               Success.  "*mostRecent" is set.
 *      else            <errno.h> error code.
 */
int pq_getMostRecent(
    pqueue* const       pq,
    timestampt* const   mostRecent);

/*
 * Returns metrics associated with the minimum virtual residence time of
 * data-products in the queue since the queue was created or the metrics reset.
 * The virtual residence time of a data-product is the time that the product
 * was removed from the queue minus the time that the product was created.  The
 * minimum virtual residence time is the minimum of the virtual residence times
 * over all applicable products.
 *
 * Arguments:
 *      pq              Pointer to the product-queue structure.  Shall not be
 *                      NULL.
 *      minVirtResTime  Pointer to the minimum virtual residence time of the
 *                      queue since the queue was created.  Shall not be NULL.
 *                      "*minVirtResTime" is set upon successful return.  If
 *                      such a time doesn't exist (because no products have
 *                      been deleted from the queue, for example), then
 *                      "*minVirtResTime" shall be TS_NONE upon successful
 *                      return.
 *      size            Pointer to the amount of data used, in bytes, when the
 *                      minimum virtual residence time was set. Shall not be
 *                      NULL. Set upon successful return. If this parameter
 *                      doesn't exist, then "*size" shall be set to -1.
 *      slots           Pointer to the number of slots used when the minimum
 *                      virtual residence time was set. Shall not be NULL. Set
 *                      upon successful return. If this parameter doesn't exist,
 *                      the "*slots" shall be set to 0.
 * Returns:
 *      0               Success.  All the outout metrics are set.
 *      else            <errno.h> error code.
 */
int pq_getMinVirtResTimeMetrics(
    pqueue* const       pq,
    timestampt* const   minVirtResTime,
    off_t* const        size,
    size_t* const       slots);

/*
 * Clears the metrics associated with the minimum virtual residence time of
 * data-products in the queue.  After this function, the minimum virtual
 * residence time metrics will be recomputed as products are deleted from the
 * queue.
 *
 * Arguments:
 *      pq              Pointer to the product-queue structure.  Shall not be
 *                      NULL.  Must be open for writing.
 * Returns:
 *      0               Success.  The minimum virtual residence time metrics are
 *                      cleared.
 *      else            <errno.h> error code.
 */
int pq_clearMinVirtResTimeMetrics(
    pqueue* const       pq);

/*
 * Get some detailed product queue statistics.  These may be useful for
 * monitoring the internal state of the product queue:
 *   nprodsp
 *         holds the current number of products in the queue.  May be NULL.
 *   nfreep
 *         holds the current number of free regions.  This should be small
 *         and it's OK if it's zero, since new free regions are created
 *         as needed by deleting oldest products.  If this gets large,
 *         insertion and deletion take longer.  May be NULL.
 *   nemptyp
 *         holds the number of product slots left.  This may decrease, but
 *         should eventually stay above some positive value unless too
 *         few product slots were allocated when the queue was
 *         created.  New product slots get created when adjacent free
 *         regions are consolidated, and product slots get consumed
 *         when larger free regions are split into smaller free
 *         regions.  May be NULL.
 *   nbytesp
 *         holds the current number of bytes in the queue used for data
 *         products.  May be NULL.
 *   maxprodsp
 *         holds the maximum number of products in the queue, so far.  May be
 *         NULL.
 *   maxfreep
 *         holds the maximum number of free regions, so far.  May be NULL.
 *   minemptyp
 *         holds the minimum number of empty product slots, so far.  May be
 *         NULL.
 *   maxbytesp
 *         holds the maximum number of bytes used for data, so far.  May be
 *         NULL.
 *   age_oldestp
 *         holds the age in seconds of the oldest product in the queue.  May be
 *         NULL.
 *   maxextentp
 *         holds extent of largest free region  May be NULL.
 *
 *   Note: the fixed number of slots allocated for products when the
 *         queue was created is nalloc = (nprods + nfree + nempty).
 */
int
pq_stats(pqueue *pq,
     size_t* const      nprodsp,
     size_t* const      nfreep,
     size_t* const      nemptyp,
     size_t* const      nbytesp,
     size_t* const      maxprodsp,
     size_t* const      maxfreep,
     size_t* const      minemptyp,
     size_t* const      maxbytesp,
     double* const      age_oldestp,
     size_t* const      maxextentp);

/*
 * Returns the number of slots in a product-queue.
 *
 * Arguments:
 *      pq              Pointer to the product-queue object.
 * Returns:
 *      The number of slots in the product-queue.
 */
size_t
pq_getSlotCount(
    pqueue* const       pq);

/*
 * Returns the insertion-timestamp of the oldest data-product in the
 * product-queue.
 *
 * Arguments:
 *      oldestCursor    Pointer to structure to received the insertion-time
 *                      of the oldest data-product.
 * Returns:
 *      ENOERR          Success.
 *      else            Failure.
 */
int
pq_getOldestCursor(
    pqueue*             pq,
    timestampt* const   oldestCursor);

/*
 * Returns the number of pq_open()s for writing outstanding on an existing
 * product queue.  If a writing process terminates without calling pq_close(),
 * then the actual number will be less than this number.  This function opens
 * the product-queue read-only, so if there are no outstanding product-queue
 * writers, then the returned count will be zero.
 *
 * Arguments:
 *      path    The pathname of the product-queue.
 *      count   The memory to receive the number of writers.
 * Returns:
 *      0           Success.  *count will be the number of writers.
 *      EINVAL      path is NULL or count is NULL.  *count untouched.
 *      ENOSYS      Function not supported because product-queue doesn't support
 *                  writer-counting.
 *      PQ_CORRUPT  The  product-queue is internally inconsistent.
 *      else        <errno.h> error-code.  *count untouched.
 */
int
pq_get_write_count(
    const char* const   path,
    unsigned* const     count);

/*
 * Sets to zero the number of pq_open()s for writing outstanding on the
 * product-queue.  This is a dangerous function and should only be used when
 * it is known that there are no outstanding pq_open()s for writing on the
 * product-queue.
 *
 * Arguments:
 *      path    The pathname of the product-queue.
 * Returns:
 *      0           Success.
 *      EINVAL      path is NULL.
 *      PQ_CORRUPT  The  product-queue is internally inconsistent.
 *      else        <errno.h> error-code.
 */
int
pq_clear_write_count(const char* const path);

/*
 * For debugging: dump extents of regions on free list, in order by extent.
 */
int
pq_fext_dump(pqueue *const pq);

/*
 * Set cursor used by pq_sequence() or pq_seqdel().
 */
void
pq_cset(pqueue *pq, const timestampt *tvp);

/*
 * Set cursor_offset used by pq_sequence() to disambiguate among
 * multiple products with identical queue insertion times.
 */
void
pq_coffset(pqueue *pq, off_t c_offset);

/*
 * Get current cursor value used by pq_sequence() or pq_seqdel().
 */
void
pq_ctimestamp(const pqueue *pq, timestampt *tvp);

/*
 * Figure out the direction of scan of clssp, and set *mtp to it.
 * Set the cursor to include all of clssp time range in the queue.
 * (N.B.: For "reverse" scans, this range may not include all
 * the arrival times.)
 */
int
pq_cClassSet(pqueue *pq,  pq_match *mtp, const prod_class_t *clssp);

/*
 * Set the cursor based on the insertion-time of the product with the given
 * signature if and only if the associated data-product is found in the 
 * product-queue.
 *
 * Arguments:
 *      pq              Pointer to the product-queue.
 *      signature       The given signature.
 * Returns:
 *      0       Success.  The cursor is set to reference the data-product with
 *              the same signature as the given one.
 *      EACCES  "pq->fd" is not open for read or "pq->fd" is not open for write
 *              and PROT_WRITE was specified for a MAP_SHARED type mapping.
 *      EAGAIN  The mapping could not be locked in memory, if required by
 *              mlockall(), due to a lack of resources.
 *      EBADF   "pq->fd" is not a valid file descriptor open for reading.
 *      EDEADLK The necessary lock is blocked by some lock from another process
 *              and putting the calling process to sleep, waiting for that lock
 *              to become free would cause a deadlock.
 *      EFBIG or EINVAL
 *              The extent of the region is greater than the maximum file size.
 *      EFBIG   The file is a regular file and the extent of the region is
 *              greater than the offset maximum established in the open file
 *              description associated with "pq->fd".
 *      EINTR   A signal was caught during execution.
 *      EINVAL  The region's offset or extent is not valid, or "pq->fd" refers
 *              to a file that does not support locking.
 *      EINVAL  The region's offset is not a multiple of the page size as 
 *              returned by sysconf(), or is considered invalid by the 
 *              implementation.
 *      EIO     An I/O error occurred while reading from the file system.
 *      EIO     The metadata of a data-product in the product-queue could not be
 *              decoded.
 *      EMFILE  The number of mapped regions would exceed an
 *              implementation-dependent limit (per process or per system).
 *      ENODEV  "pq->fd" refers to a file whose type is not supported by mmap().
 *      ENOLCK  Satisfying the request would result in the number of locked
 *              regions in the system exceeding a system-imposed limit.
 *      ENOMEM  There is insufficient room in the address space to effect the
 *              necessary mapping.
 *      ENOMEM  The region's mapping could not be locked in memory, if required
 *              by mlockall(), because it would require more space than the 
 *              system is able to supply.
 *      ENOMEM  Insufficient memory is available.
 *      ENOTSUP The implementation does not support the access requested in
 *              "pq->pflags".
 *      ENXIO   The region's location is invalid for the object specified by
 *              "pq->fd".
 *      EOVERFLOW
 *              The smallest or, if the region's extent is non-zero, the
 *              largest offset of any byte in the requested segment cannot be
 *              represented correctly in an object of type off_t.
 *      EOVERFLOW
 *              The file size in bytes or the number of blocks allocated to the
 *              file or the file serial number cannot be represented correctly.
 *      EOVERFLOW
 *              The file is a regular file and the region's offset plus 
 *              extent exceeds the offset maximum established in the open file
 *              description associated with "fd". 
 *      EROFS   The file resides on a read-only file system.
 *
 *      PQ_CORRUPT
 *              The product-queue is corrupt.
 *      PQ_NOTFOUND
 *              A data-product with the given signature was not found in the
 *              product-queue.
 */
int
pq_setCursorFromSignature(
    pqueue* const       pq,
    const signaturet    signature);

/*
 * Step thru the time sorted inventory according to 'mt',
 * and the current cursor value.
 *
 * If(mt == TV_LT), pq_sequence() will get a product
 * whose queue insertion timestamp is strictly less than
 * the current cursor value.
 *
 * If(mt == TV_GT), pq_sequence() will get a product
 * whose queue insertion timestamp is strictly greater than
 * the current cursor value.
 *
 * If(mt == TV_EQ), pq_sequence() will get a product
 * whose queue insertion timestamp is equal to
 * the current cursor value.
 *
 * If no product is in the inventory which which meets the
 * above spec, return PQUEUE_END.
 *
 * Otherwise, if the product info matches class,
 * execute ifMatch(xprod, len, otherargs) and return the
 * return value from ifMatch().
 */
int
pq_sequence(pqueue *pq, pq_match mt,
        const prod_class_t *clss, pq_seqfunc *ifMatch, void *otherargs);

/*
 * Boolean function to
 * check that the cursor timestime is
 * in the time range specified by clssp.
 * Returns non-zero if this is the case, zero if not.
 */
int
pq_ctimeck(const pqueue *pq, pq_match mt, const prod_class_t *clssp,
        const timestampt *maxlatencyp);

/*ARGSUSED*/
int
pq_seqdel(pqueue *pq, pq_match mt,
        const prod_class_t *clss, int wait,
        size_t *extentp, timestampt *timestampp) ;

/*
 * Returns the creation-time of the data-product in the product-queue whose
 * insertion-time is closest-to but less-than the "to" time of a class
 * specification.  Sets the cursor of the product-queue to the insertion-
 * time of the data-product, if found.
 *
 * Arguments:
 *      pq      Pointer to product-queue open for reading.
 *      clssp   Pointer to selection-criteria.
 *      tsp     Pointer to timestamp.  Set to creation-time of first, matching
 *              data-product; otherwise, unmodified.
 * Returns:
 *      0       Success (maybe).  *tsp is modified if and only if a matching 
 *              data-product was found.
 *      else    Failure.  <errno.h> error-code.
 */
int
pq_last(pqueue *pq,
        const prod_class_t *clssp,
        timestampt *tsp) /* modified upon return */;

/*
 * Modifies a data-product class-specification according to the most recent
 * data-product in the product-queue that matches the specification.
 *
 * The product-queue cursor is unconditionally cleared.
 *
 * Arguments:
 *      pq              Pointer to the product-queue.
 *      clssp           Pointer to the data-product class-specification.
 *                      Modified on and only on success.
 * Returns:
 *      0               Success.  "clssp" is modified.
 *      PQUEUE_END      There's no matching data-product in the product-queue.
 *      else            <errno.h> error-code.
 */
int
pq_clss_setfrom(pqueue *pq,
         prod_class_t *clssp)     /* modified upon return */;

/*
 * Suspend yourself (sleep) until
 * one of the following events occurs:
 *   You recieve a signal that you handle.
 *   You recieve SIGCONT (sent from an insert proc indicating
 *      data is available).
 *   "maxsleep" seconds elapse.
 *   If "maxsleep" is zero, you could sleep forever. 
 * Returns the requested amount of suspension-time minus the amount of time 
 * actually suspended.
 */
unsigned
pq_suspend(unsigned int maxsleep);

/*ARGSUSED*/
const char*
pq_strerror(
    const pqueue* const pq,
    const int           error);

#ifdef __cplusplus
}
#endif

#endif /* !_PQ_H */
