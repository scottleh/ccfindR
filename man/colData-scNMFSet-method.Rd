% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/scNMF_class.R
\docType{methods}
\name{colData,scNMFSet-method}
\alias{colData,scNMFSet-method}
\title{Sample annotation accessor}
\usage{
\S4method{colData}{scNMFSet}(x)
}
\arguments{
\item{x}{Object containing sample annotation}
}
\value{
Column annotation DataFrame
}
\description{
Sample annotation accessor
}
\examples{
library(S4Vectors)
x <- matrix(rpois(n=12,lambda=3),4,3)
rownames(x) <- seq_len(4)
colnames(x) <- c('a','b','c')
s <- scNMFSet(count=x,rowData=seq_len(4),colData=c('a','b','c'))
cols <- DataFrame(tissue=c('tissue1','tissue1','tissue2'))
rownames(cols) <- c('a','b','c')
colData(s) <- cols
s
}
