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

    // Guard against out-of-bounds starting index
    if (idx_nxt < 0 || idx_nxt >= isize) {
      dist_down[j] = 0.0;
      return;
    }

    double dist_tmp = d_nxt[idx_nxt];
    std::vector<int8_t> visited(isize, 0);
    int max_iter = isize;
    int iter = 0;

    while (iter < max_iter) {
      // Cycle detection: stop if we revisit a node
      if (visited[idx_nxt]) break;
      visited[idx_nxt] = true;

      // Bounds check
      if (idx_nxt < 0 || idx_nxt >= isize) break;

      // Float comparison tolerance for mouth detection
      if (std::abs(isMouth[idx_nxt] - 1.0) < 1e-9) break;

      dist_tmp += d_nxt[idx_nxt];
      idx_nxt = idx_nxt_tmp[idx_nxt];
      iter++;
    }
    dist_down[j] = dist_tmp;
  }, 6);

  return dist_down;
}
