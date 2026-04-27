#include <Rcpp.h>
#include <RcppThread.h>
#include <vector>

using namespace Rcpp;

// [[Rcpp::plugins(cpp11)]]
// [[Rcpp::export]]
NumericVector calc_ld_cpp(NumericVector i,
                          NumericVector isMouth,
                          NumericVector d_nxt,
                          NumericVector idx_nxt_tmp,
                          int total_nodes) {

  int isize = i.size();
  NumericVector dist_down(isize);

  RcppThread::parallelFor(0, isize, [&] (int j) {
    int current_idx = i[j];

    // Guard against out-of-bounds starting index
    if (current_idx < 0 || current_idx >= total_nodes) {
      dist_down[j] = 0.0;
      return;
    }

    double dist_tmp = 0.0;
    std::vector<int8_t> visited(total_nodes, 0);
    int max_iter = total_nodes;
    int iter = 0;
    int idx_working = current_idx;

    while (iter < max_iter) {
      if (idx_working < 0 || idx_working >= total_nodes) break;
      if (visited[idx_working]) break; // Cycle detection
      
      visited[idx_working] = 1;
      
      // If it's a mouth, we stop
      if (isMouth[idx_working] > 0.5) break;
      
      // Add distance to next node
      dist_tmp += d_nxt[idx_working];
      
      // Move to next node
      idx_working = idx_nxt_tmp[idx_working];
      iter++;
    }
    dist_down[j] = dist_tmp;
  }, 6);

  return dist_down;
}
