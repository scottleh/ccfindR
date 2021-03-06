# Update hyperparameters
hyper_update <- function(hyper.update, wh, hyper, Niter=100, Tol=1e-4){
    
   if(sum(hyper.update)==0) return(hyper)
  
   aw0 <- hyper$aw
   ah0 <- hyper$ah
   lwm <- mean(log(wh$lw))
   lhm <- mean(log(wh$lh))
   ewm <- mean(wh$ew)
   ehm <- mean(wh$eh)
   bw0 <- hyper$bw
   bh0 <- hyper$bh
  
   if(hyper.update[1]+hyper.update[3]>0){
    i <- 1
    while(i<Niter){
      if(hyper.update[1])
        dw <- (log(aw0)-digamma(aw0)-ewm/bw0+1+lwm-log(bw0))/
          (1/aw0-psigamma(aw0,1))
      else dw <- 0
      if(hyper.update[3])
        dh <- (log(ah0)-digamma(ah0)-ehm/bh0+1+lhm-log(bh0))/
          (1/ah0-psigamma(ah0,1))
      else dh <- 0
      aw1 <- aw0 - dw 
      ah1 <- ah0 - dh
      while(aw1<=0){
        dw <- dw/2
        aw1 <- aw0 - dw 
      }
      while(ah1<=0){
        dh <- dh/2
        ah1 <- ah0 - dh
      }
      
      df <- mean((1-aw1/aw0)^2)+mean((1-ah1/ah0)^2)
      if(df<Tol) break
      aw0 <- aw1
      ah0 <- ah1
      i <- i+1
    }
    if(i==Niter) stop('Hyper-parameter update failed to converge')
   } else{
     aw1 <- aw0
     ah1 <- ah0
   }
   if(hyper.update[2]) bw1 <- ewm
   else bw1 <- bw0
   if(hyper.update[4]) bh1 <- ehm
   else bh1 <- ehm
   list(aw=aw1, bw=bw1, ah=ah1, bh=bh1)
}

# Single update step in Bayesian NMF inference
vbnmf_updateR <- function(x, wh, r, hyper, fudge=NULL){

   x <- as.matrix(x)
   n <- dim(x)[1]
   m <- dim(x)[2]

   lw <- as.matrix(wh$lw)
   lh <- as.matrix(wh$lh)
   ew <- as.matrix(wh$ew)
   eh <- as.matrix(wh$eh)
   aw <- hyper$aw
   bw <- hyper$bw
   ah <- hyper$ah
   bh <- hyper$bh
  
   wth <- lw %*% lh
   sw <- lw*((x/wth) %*% t(lh))
   sh <- lh*(t(lw) %*% (x/wth))
  
   alw <- aw + sw
   bew <- 1/(aw/bw + t(replicate(n, rowSums(eh))))
   ew <- alw*bew             # this update needs to precede lines below
  
   alh <- ah + sh
   beh <- 1/(ah/bh + replicate(m, colSums(ew)))
   eh <- alh*beh

   lw <- exp(digamma(alw))*bew
   lh <- exp(digamma(alh))*beh
   if(is.null(fudge)) fudge <- .Machine$double.eps
   lw[lw < fudge] <- fudge
   lh[lh < fudge] <- fudge
    
   wth <- lw %*% lh
   U1 <- -ew %*% eh - lgamma(x+1) - x*((((lw*log(lw))%*%lh) + 
          lw%*%(lh*log(lh)))/wth - log(wth))
   U2 <- -(aw/bw)*ew - lgamma(aw) + aw*log(aw/bw) + 
    alw*(1+log(bew))+lgamma(alw)
   U3 <- -(ah/bh)*eh - lgamma(ah) + ah*log(ah/bh) + 
    alh*(1+log(beh))+lgamma(alh)
   U <- sum(U1) + sum(U2) + sum(U3)
   U <- U/(n*m)  # log evidence per feature per cell
  
   w <- ew    
   h <- eh
   
   dw <- alw*bew^2
   dh <- alh*beh^2
    
   list(w=w, h=h, lw=lw, lh=lh, ew=ew, eh=eh, lkh=U, dw=dw, dh=dh)
}

# Initialize bNMF inference
vb_init <- function(nrow,ncol,mat,rank, max=1.0, hyper, initializer){
  
   if(initializer=='random'){
     w <- matrix(stats::rgamma(n=nrow*rank, shape=hyper$aw, 
           scale=hyper$bw/hyper$aw), nrow=nrow,ncol=rank)
     h <- matrix(stats::rgamma(n=rank*ncol, shape=hyper$ah, 
           scale=hyper$bh/hyper$ah), nrow=rank,ncol=ncol)
   } else if(initializer=='svd'){
     w <- matrix(0, nrow=nrow, ncol=rank)
     h <- matrix(0, nrow=rank, ncol=ncol)
     s <- svd(mat, nu=rank, nv=rank)
     d1 <- sqrt(s$d[1])
     w[,1] <- d1*s$u[,1]
     sgn <- sign(w[1,1])
     if(sgn<0) w <- -w
     h[1,] <- sgn*d1*s$v[,1]
     for(k in seq(2,rank)){
       x <- s$u[,k]
       y <- s$v[,k]
       xp <- vapply(x,function(x){if(x>0) x else 0},numeric(1))
       yp <- vapply(y,function(x){if(x>0) x else 0},numeric(1))
       xn <- vapply(x,function(x){if(x<0) -x else 0},numeric(1))
       yn <- vapply(y,function(x){if(x<0) -x else 0},numeric(1))
       xpnrm <- sqrt(sum(xp^2))
       ypnrm <- sqrt(sum(yp^2))
       mp <- xpnrm*ypnrm
       xnnrm <- sqrt(sum(xp^2))
       ynnrm <- sqrt(sum(yp^2))
       mn <- xnnrm*ynnrm
       if(mp>=mn){
         u <- xp/xpnrm
         v <- yp/ypnrm
         sig <- mp
       }else{
         u <- xn/xnnrm
         v <- yn/ynnrm
         sig <- mn
       }
       w[,k] <- sqrt(s$d[k]*sig)*u
       h[k,] <- sqrt(s$d[k]*sig)*t(v)
     }
   } else if(initializer=='svd2'){
     if(min(nrow,ncol)/2 <= rank)
       s <- svd(mat, nu=rank, nv=rank)
     else
       s <- irlba::irlba(mat, rank)
     w <- abs(s$u)
     h <- abs(diag(s$d[seq_len(rank)]) %*% t(s$v))
     scale <- hyper$bh/mean(h)
     h <- h*scale
     w <- w/scale
   }else stop('Unknown initializer')
  
   dw <- matrix(0, nrow=nrow, ncol=rank)
   dh <- matrix(0, nrow=rank, ncol=ncol)

   rownames(w) <- rownames(dw) <- rownames(mat)
   colnames(w) <- colnames(dw) <- seq_len(rank)
   rownames(h) <- rownames(dh) <- seq_len(rank)
   colnames(h) <- colnames(dh) <- colnames(mat)
  
   list(w=w, h=h, lw=w, lh=h, ew=w, eh=h, dw=dw, dh=dh)
}

#' Bayesian NMF inference of count matrix
#' 
#' Perform variational Bayes NMF and store factor matrices in object
#' 
#' The main input is the \code{scNMFSet} object with count matrix.
#' This function performs non-negative factorization using Bayesian algorithm
#' and gamma priors. Slots \code{basis}, \code{coeff}, and \code{ranks} 
#' are filled.
#' 
#' @param object \code{scNMFSet} object containing count matrix.
#' @param ranks Rank for factorization; can be a vector of multiple values.
#' @param nrun No. of runs with different initial guesses.
#' @param verbose The verbosity level: 
#'        3, each iteration output printed;
#'        2, each run output printed; 
#'        1, each randomized sample output printed;
#'        0, silent.
#' @param progress.bar Display progress bar with \code{verbose = 1} for 
#'       multiple runs.
#' @param initializer If \code{'random'}, randomized initial conditions; 
#'        \code{'svd2'} for singular value decomposed initial condition.
#' @param Itmax Maximum no. of iteration.
#' @param hyper.update Vector of four logicals, each indcating whether
#'        hyperparameters \code{c(aw, bw, ah, bh)} should be optimized.
#' @param gamma.a Gamma distribution shape parameter.
#' @param gamma.b Gamma distribution mean. These two parameters are used for 
#'        fixed hyperparameters with \code{hyper.update} elements \code{FALSE}.
#' @param Tol Tolerance for terminating iteration.
#' @param hyper.update.n0 Initial number of steps in which hyperparameters 
#'        are fixed.
#' @param hyper.update.dn Step intervals for hyperparameter updates.
#' @param connectivity If \code{TRUE}, connectivity and dispersion will
#'        be calculated after each run. Can be turned off to save memory.
#' @param fudge Small positive number used as lower bound for factor matrix 
#'        elements to avoid singularity. If \code{fudge = NULL} (default), 
#'        it will be replaced by \code{.Machine$double.eps}. 
#'        Can be set to 0 to skip 
#'        regularization.
#' @param ncores Number of processors (cores) to run. If \code{ncores > 1},
#'        parallelization is attempted.
#' @param useC  Use C++ version of updates for speed.
#' @param unif.stop Terminate if any of columns in basis matrix is uniform.
#' @return Object of class \code{scNMFSet} with factorization slots filled.
#' 
#' @details When run with multiple values of \code{ranks}, factorization is 
#'        repeated for each rank and the slot \code{measure} contains 
#'        log evidence and optimal hyperparameters for each rank. 
#'        With \code{nrun > 1}, the solution
#'        with the maximum log evidence is stored for a given rank.
#' @examples
#' set.seed(1)
#' x <- simulate_whx(nrow=50,ncol=100,rank=5)
#' s <- scNMFSet(x$x)
#' s <- vb_factorize(s,ranks=seq(2,8),nrun=5)
#' plot(s)
#' @export
vb_factorize <- function(object, ranks=2, nrun=1, verbose=2, 
                         progress.bar=TRUE, initializer='random',
                         Itmax=10000, hyper.update=rep(TRUE,4), 
                         gamma.a=1, gamma.b=1, Tol=1e-5, 
                         hyper.update.n0=10, hyper.update.dn=1, 
                         connectivity=TRUE, fudge=NULL,
                         ncores=1, useC=TRUE,
                         unif.stop=TRUE){
  
   if(is.null(fudge)) fudge <- .Machine$double.eps
   mat <- counts(object) # S4 class scNMFSet
   
   if(initializer %in% c('svd','svd2') & nrun > 1)
     stop('SVD initializer does not require nrun > 1')
  
   nullr <- sum(Matrix::rowSums(mat)==0)
   nullc <- sum(Matrix::colSums(mat)==0)
   if(nullr>0) stop('Input matrix contains empty rows')
   if(nullc>0) stop('Input matrix contains empty columns')
   
   ranks <- ranks[ranks <= ncol(mat)] # rank <= no. of columns
   nrank <- length(ranks)
   
   bundle <- list(mat=mat, ranks=ranks, verbose=verbose, gamma.a=gamma.a,
                  gamma.b=gamma.b, initializer=initializer, 
                  connectivity=connectivity, 
                  Itmax=Itmax, fudge=fudge, useC=useC,
                  hyper.update=hyper.update, 
                  hyper.update.n0=hyper.update.n0, 
                  ncores=ncores, hyper.update.dn=hyper.update.dn, Tol=Tol,
                  unif.stop=unif.stop, nrun=nrun)
   if(ncores==1)
     vb <- lapply(seq_len(nrun), FUN=vb_iterate, bundle)
   else    # parallel
     vb <- Rmpi::mpi.applyLB(seq_len(nrun), FUN=vb_iterate, bundle)

   basis <- dbasis <- coeff <- dcoeff <- vector('list',nrank)
   rdat <- awdat <- bwdat <- ahdat <- bhdat <- nunif <- c()
   ranks2 <- c()
   for(k in seq_len(nrank)){     # find maximum solutions for each rank
     rmax <- -Inf
     for(i in seq_len(nrun)){
       if(vb[[i]]$rdat[k] > rmax){
         imax <- i
         rmax <- vb[[i]]$rdat[k]
       }
     }
     if(rmax==-Inf) next
     ranks2 <- c(ranks2,ranks[k])
     rdat <- c(rdat,rmax)
     basis[[k]] <- vb[[imax]]$wdat[[k]]
     coeff[[k]] <- vb[[imax]]$hdat[[k]]
     dbasis[[k]] <- vb[[imax]]$dwdat[[k]]
     dcoeff[[k]] <- vb[[imax]]$dhdat[[k]]
     awdat <- c(awdat, vb[[imax]]$hyperp[[k]]$aw)
     bwdat <- c(bwdat, vb[[imax]]$hyperp[[k]]$bw)
     ahdat <- c(ahdat, vb[[imax]]$hyperp[[k]]$ah)
     bhdat <- c(bhdat, vb[[imax]]$hyperp[[k]]$bh)
     nunif <- c(nunif, vb[[imax]]$nunif[k])
     
     rownames(basis[[k]]) <- rownames(dbasis[[k]]) <- rownames(mat)
     colnames(coeff[[k]]) <- colnames(dcoeff[[k]]) <- colnames(mat)
   }
   
   object@ranks <- ranks2
   object@basis <- basis
   object@dbasis <- dbasis
   object@coeff <- coeff
   object@dcoeff <- dcoeff
   object@measure <- data.frame(rank=ranks2, lml=rdat, aw=awdat, bw=bwdat, 
                                ah=ahdat, bh=bhdat, nunif=nunif)
   return(object)
}

vb_iterate <- function(irun, bundle){
  
   nrow <- dim(bundle$mat)[1]
   ncol <- dim(bundle$mat)[2]
   nrank <- length(bundle$ranks)
   
   rdat <- rep(-Inf, nrank)
   wdat <- hdat <- dwdat <- dhdat <- hyperp <- list()
   nunif <- rep(0, nrank)
   
   if(bundle$verbose >= 2) if(bundle$nrun > 1) 
     cat('Run ',irun,'\n',sep='')
   
   for(irank in seq_len(nrank)){
     
     rank <- bundle$ranks[[irank]]
     if(rank > min(nrow,ncol))
       stop('Rank exceeded min(nrow,ncol)')
     aw <- bundle$gamma.a[1]
     ah <- bundle$gamma.a[length(bundle$gamma.a)]
     bw <- bundle$gamma.b[1]
     bh <- bundle$gamma.b[length(bundle$gamma.b)]
     
     hyper <- hyper0 <- list(aw=aw, bw=bw, ah=ah, bh=bh)
       
     if(bundle$connectivity){
       npair <- ncol*(ncol-1)/2
       conav <- rep(0, npair)
     }

     hyper <- hyper0
     wh <- vb_init(nrow, ncol, bundle$mat, rank, hyper=hyper, 
                   initializer=bundle$initializer)
     lk0 <- 0
     for(it in seq_len(bundle$Itmax)){
       if(bundle$useC)
         wh <- vbnmf_update(as.matrix(bundle$mat),wh,hyper,c(bundle$fudge))
       else
         wh <- vbnmf_updateR(bundle$mat, wh, rank, hyper, fudge=bundle$fudge)
       if(it > bundle$hyper.update.n0 & it%%bundle$hyper.update.dn==0) 
         hyper <- hyper_update(bundle$hyper.update, wh, hyper, Niter=100, 
                            Tol=1e-3)
       if(is.na(wh$lkh)) break
       if(it>1) if(it > bundle$hyper.update.n0)
          if(wh$lkh>=lk0) if(abs(1-wh$lkh/lk0) < bundle$Tol) break
       lk0 <- wh$lkh
       if(bundle$verbose >= 3) cat(it,', log(evidence) = ',lk0,', aw = ',
                     hyper$aw,', bw = ',hyper$bw,', ah = ',hyper$ah,
                     ', bh = ',hyper$bh, '\n',sep='')
     }
     if(bundle$connectivity){
       cnn <- connectivity(wh$eh)
       conav <- conav + cnn
       disp <- dispersion(conav/irun,ncol)
     }
     if(bundle$verbose >= 2){
       if(bundle$connectivity) cat('Rank = ',rank,
                                    ': Nsteps =',it,', log(evidence) =',lk0,
                         ', hyper = (',hyper$aw,',',hyper$bw,',',hyper$ah,',',
                         hyper$bh,')', ', dispersion = ',disp,'\n',sep='')
       else cat('Rank = ',rank, ': Nsteps =',it,', log(evidence) =',lk0,
             ', hyper = (',hyper$aw,',',hyper$bw,',',hyper$ah,',',
             hyper$bh,')\n',sep='')
     }
     
     contains.unif <- apply(wh$ew,2,
                              function(x){abs(max(x)-min(x))<bundle$Tol})
     if(sum(contains.unif)>0){
       warning('Rank ',rank,' row/column ',
              paste(which(contains.unif),collapse=','),' constant.')
       if(bundle$unif.stop){
         warning('Rank scan stopped for rank >= ',rank)
         if(irank==1) stop('Rerun with lower ranks')
         break
       }
     }
     rdat[irank] <- lk0
     wdat[[irank]] <- wh$ew
     hdat[[irank]] <- wh$eh
     dwdat[[irank]] <- sqrt(wh$dw)
     dhdat[[irank]] <- sqrt(wh$dh) 
     hyperp[[irank]] <- hyper
   }   # end of irank-loop
   
   vb <- list(rdat=rdat, wdat=wdat, hdat=hdat, hyperp=hyperp, nunif=nunif,
              dwdat=dwdat,dhdat=dhdat)
   return(vb)
}
