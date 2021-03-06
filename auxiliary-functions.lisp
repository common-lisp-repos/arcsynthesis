(in-package #:arc)

;; from nikki93's github.com/nikki93/lgame/blob/master/game.lisp
;; this supposedly solves live editing problems for all the three main OS's
;; but on windows "single threaded mode" must be forced:
;; (setf *swank:*communication-style* nil) in ~/.swank.lisp
(defmacro with-main (&body body)
  "Enables REPL access via UPDATE-SWANK in the main loop using SDL2. Wrap this around
the sdl2:with-init code."
  ;;TODO: understand this. Without this wrapping the sdl:with-init the sdl thread
  ;; is an "Anonymous thread" (tested using sb-thread:*current-thread*), while applying
  ;; this makes *current-thread* the same as the one one when queried directly from the
  ;; REPL thread: #<SB-THREAD:THREAD "repl-thread" RUNNING {adress...}>
  `(sdl2:make-this-thread-main
    (lambda ()
      ;; does work on linux+sbcl without the following line:
      #+sbcl (sb-int:with-float-traps-masked (:invalid) ,@body)
      #-sbcl ,@body)))


(defmacro continuable (&body body)
  "Helper macro that we can use to allow us to continue from an
  error. Remember to hit C in slime or pick the restart so errors don't kill the
  app."
  `(restart-case
       (progn ,@body) (continue () :report "Continue")))

(defun update-swank ()
  "Called from within the main loop, this keeps the lisp repl
working while cepl runs"
  (continuable
   (let ((connection
	  (or swank::*emacs-connection*
	      (swank::default-connection))))
     (when connection
       (swank::handle-requests connection t)))))

;; TODO: (gl:foreign-alloc ...  :initial-contents)
(defun fill-gl-array (gl-array data-array)
  "Fills gl-array <gl-array> with <data-array> of type cl:array, <data-array>'s contents
will be COERCEd to SINGLE-FLOAT"
  (if (and (typep gl-array 'gl:gl-array)
	   (arrayp data-array)
           (= (gl::gl-array-size gl-array)
	      (length data-array)))
      (dotimes (i (length data-array))
	(setf
	 (gl:glaref gl-array i)
	 (coerce (aref data-array i) 'single-float)))
      (progn
	(print "couldn't fill gl-array, either size of gl-array and data-array don't")
      (print "match or they aren't of proper type"))))

(defun create-gl-array-from-vector (vector-of-floats)
  (let* ((array-length (length vector-of-floats))
	 (gl-array (gl:alloc-gl-array :float array-length)))
    (fill-gl-array gl-array vector-of-floats)
    gl-array))

;; TODO: needs some more tests
(defun create-gl-array-of-type-from-vector (v type)
  "Possible types are the cffi build-in types: 
    :char
    — Foreign Type: :unsigned-char
    — Foreign Type: :short
    — Foreign Type: :unsigned-short
    — Foreign Type: :int
    — Foreign Type: :unsigned-int
    — Foreign Type: :long
    — Foreign Type: :unsigned-long
    — Foreign Type: :long-long
    — Foreign Type: :unsigned-long-long"
  (flet ((fill-gl-array (gl-array)
	   (dotimes (i (length v))
	     (setf
	      (gl:glaref gl-array i) (aref v i)))))
    (let* ((array-length (length v))
	   (gl-array (gl:alloc-gl-array type array-length)))
      (fill-gl-array gl-array)
      gl-array)))

;;TODO: replace this function by a general purpose one:
(defun create-gl-array-of-short-from-vector (vector-of-shorts)
  (flet ((fill-gl-array-of-short (gl-array)
	   (dotimes (i (length vector-of-shorts))
	     (setf
	      (gl:glaref gl-array i)
	      (coerce (aref vector-of-shorts i) '(signed-byte 16))))))
    (let* ((array-length (length vector-of-shorts))
	   (gl-array (gl:alloc-gl-array :short array-length)))
      (fill-gl-array-of-short gl-array)
      gl-array)))

(defun create-gl-array-of-unsigned-short-from-vector (vector-of-unsigned-shorts)
  (flet ((fill-gl-array-of-short (gl-array)
	   (dotimes (i (length vector-of-unsigned-shorts))
	     (setf
	      (gl:glaref gl-array i) (aref vector-of-unsigned-shorts i)))))
    (let* ((array-length (length vector-of-unsigned-shorts))
	   (gl-array (gl:alloc-gl-array :unsigned-short array-length)))
      (fill-gl-array-of-short gl-array)
      gl-array)))


;;TODO: combine many shader objects just by repeatedly calling this?
;;      why (list const-string-shader-file), is it for program of multiple string or
;;      for multiple one string programs?
;;; ATTENTION: can only be used when OpenGL context exists "somewhere" lol
(defun create-shader (e-shader-type const-string-shader-file)
  "Create and RETURN shader"
  (let ((shader (gl:create-shader e-shader-type)))
    (format t "shader:~a~%" shader) ;why is it always 0
    ;; feed const-string-shader-file into shader object (as in OpenGL object)
    (gl:shader-source shader const-string-shader-file) ;it expects a string-LIST
    (%gl:compile-shader shader)
    ;; was the compilation successful?
    (if (gl:get-shader shader :compile-status)
      (format t "~a compilation successful~%" e-shader-type)
      (format t "Compilation failure in ~a:~% ~a~%"
	      e-shader-type
	      (gl:get-shader-info-log shader)))
    shader))


(defun create-program (shader-list)
  "Create a GL program."
  (let ((program (%gl:create-program)))
    ;; "attach" all of the created shader objects to the program object
    (loop for shader-object in shader-list
       do (%gl:attach-shader program shader-object))
    ;; I guess links all the attached shaders to actually form a program object
    (%gl:link-program program)
    (if (gl:get-program program :link-status)
	(format t "Linking successful! (program object)~%")
	(format t "~a~%" (gl:get-program-info-log program)))
    ;; remove shader objects from program:
    (loop for shader-object in shader-list
       do (%gl:detach-shader program shader-object))
    program))

;; TODO: remove from all code, find solution to do such clean-ups more organized in the
;;       future. UPDATE: use SLIME'S C-c C-w C-c aka slime-who-calls (basically inverse of M-.)
(defun create-program-and-return-it (shader-list)
  (create-program shader-list))

;; stolen from cbaggers ;;TODO: aha, give an &optional asdf/system:system-source-directory !!
;; and let it merge it with <path> !!
(defun file-to-string (path)
  "Sucks up an entire file from PATH into a freshly-allocated
string, returning two values: the string and the number of
bytes read."
  (with-open-file (s path)
    (let* ((len (file-length s))
	   (data (make-string len)))
      (values data (read-sequence data s)))))

(defun gl-array-content (gl-array)
  "Returns list of gl-array's content."
  (loop for i from 0 below (gl::gl-array-size gl-array) collecting
       (gl:glaref gl-array i)))

(defmacro string-case (str &body cases)
  `(loop for i in (quote ,cases)
      when (string-equal ,str (car i))
       return (cadr i)))

(defun string->gl-type (string)
  (string-case string
    ("ushort" :unsigned-short)
    ("triangles" :triangles)
    ("float" :float)
    ("tri-fan" :triangle-fan)
    ("tri-strip" :triangle-strip)))
