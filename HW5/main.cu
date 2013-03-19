#include <cstdlib>
#include <iostream>
#include <cstdio>
#include <fstream>
#include "utils.h"
#include "timer.h"
#include <cstdio>
#if defined(_WIN16) || defined(_WIN32) || defined(_WIN64)
#include <Windows.h>
#else
#include <sys/time.h>
#endif

#include <thrust/random/linear_congruential_engine.h>
#include <thrust/random/normal_distribution.h>
#include <thrust/random/uniform_int_distribution.h>

#include "reference.h"

void computeHistogram(const unsigned int *const d_vals,
                      unsigned int* const d_histo,
                      const unsigned int numBins,
                      const unsigned int numElems);

int main(int argc, char **argv) {

  if (argc != 2) {
    std::cerr << "You must supply an output file" << std::endl;
    exit(1);
  }

  const unsigned int numBins = 1024;
  const unsigned int numElems = 10000 * numBins;
  const float stddev = 100.f;

  unsigned int *vals = new unsigned int[numElems];
  unsigned int *histo = new unsigned int[numBins];

#if defined(_WIN16) || defined(_WIN32) || defined(_WIN64)
  srand(GetTickCount());
#else
  timeval tv;
  gettimeofday(&tv, NULL);

  srand(tv.tv_usec);
#endif

  //make the mean unpredictable, but close enough to the middle
  //so that timings are unaffected
  unsigned int mean = rand() % 100 + 462;

  //Output mean so that grading can happen with the same inputs
  std::cout << mean << std::endl;

  thrust::minstd_rand rng;

  thrust::random::experimental::normal_distribution<float> normalDist((float)mean, stddev);

  for (size_t i = 0; i < numElems; ++i) {
    vals[i] = std::min((unsigned int) std::max((int)normalDist(rng), 0), numBins - 1);
  }

  unsigned int *d_vals, *d_histo;

  GpuTimer timer;

  checkCudaErrors(cudaMalloc(&d_vals,    sizeof(unsigned int) * numElems));
  checkCudaErrors(cudaMalloc(&d_histo,   sizeof(unsigned int) * numBins));
  checkCudaErrors(cudaMemset(d_histo, 0, sizeof(unsigned int) * numBins));

  checkCudaErrors(cudaMemcpy(d_vals, vals, sizeof(unsigned int) * numElems, cudaMemcpyHostToDevice));

  timer.Start();
  computeHistogram(d_vals, d_histo, numBins, numElems);
  timer.Stop();
  int err = printf("%f msecs.\n", timer.Elapsed());

  if (err < 0) {
    //Couldn't print! Probably the student closed stdout - bad news
    std::cerr << "Couldn't print timing information! STDOUT Closed!" << std::endl;
    exit(1);
  }

  unsigned int *h_studentHisto = new unsigned int[numBins];

  // copy the student-computed histogram back to the host
  checkCudaErrors(cudaMemcpy(h_studentHisto, d_histo, sizeof(unsigned int) * numBins, cudaMemcpyDeviceToHost));

  unsigned int *h_vals = new unsigned int[numElems];
  unsigned int *h_refHisto = new unsigned int[numBins];

  for (size_t i = 0; i < numElems; ++i) {
    h_vals[i] = std::min((unsigned int) std::max((int)normalDist(rng), 0), numBins - 1);
  }

  //generate reference for the given mean
  reference_calculation(h_vals, h_refHisto, numBins, numElems);

  //Now do the comparison
  checkResultsExact(h_refHisto, h_studentHisto, numBins);

  delete[] h_vals;
  delete[] h_refHisto;
  delete[] h_studentHisto;

  cudaFree(d_vals);
  cudaFree(d_histo);

  return 0;
}
