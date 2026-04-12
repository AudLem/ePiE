#include <Rcpp.h>
#include <RcppThread.h>
#include <vector>

using namespace Rcpp;

// [[Rcpp::plugins(cpp11)]]
// [[Rcpp::export]]
NumericVector calc_ld_cpp(NumericVector i,
                          NumericVector isMouth,
                          NumericVector d_nxt,
                          NumericVector idx_nxt_tmp) {

  int isize = i.size();
  NumericVector dist_down(isize);

  RcppThread::parallelFor(0, isize, [&] (int j) {
    int idx_nxt = i[j];
    double dist_tmp = d_nxt[idx_nxt];
    while (true) {
      idx_nxt = idx_nxt_tmp[idx_nxt];
      if (isMouth[idx_nxt] == 1) break;
      dist_tmp += d_nxt[idx_nxt];
    }
    dist_down[j] = dist_tmp;
  }, 6);

  return dist_down;
}
