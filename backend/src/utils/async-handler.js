/**
 * WHAT: Wraps async Express handlers so rejected promises reach the error middleware.
 * WHY: This removes repeated try/catch scaffolding from controllers while preserving a single error path.
 * HOW: Return a function that forwards promise rejections into `next`.
 */

function asyncHandler(handler) {
  return function wrappedAsyncHandler(req, res, next) {
    // WHY: Forward rejected async controller promises into Express error handling without local try/catch noise.
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}

module.exports = { asyncHandler };
