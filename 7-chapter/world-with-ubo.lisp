;; TODO: about

(in-package #:arc-7.1)

;; TODO: this might solve the problem:
;; (print (uiop/lisp-build:current-lisp-file-pathname)) ?
(defvar *glsl-directory*
  (merge-pathnames #p "7-chapter/" (asdf/system:system-source-directory :arcsynthesis)))
(defvar *data-dir*
  (merge-pathnames #p "data/" *glsl-directory*))
;;todo: fix this output to slime-repl solution
(defvar out *standard-output*)  (defvar dbg *debug-io*) (defvar err *error-output*)


;;TODO: note from pjb stating to try ":conc-name" regarding a former rejection
;;       to implement program-data using defstruct, as it creates verbose symbols
(defclass program-data ()
  ((the-program :accessor the-program)
   (model-to-world-matrix-unif :accessor model-to-world-matrix-unif)
   (global-uniform-block-index :accessor global-uniform-block-index)
   (base-color-unif :accessor base-color-unif)
;   (thing :accessor thing) ;; TODO: what's the use of "thing"?
   ))


;;program-data
(defvar *uniform-color*)
(defvar *object-color*)
(defvar *uniform-color-tint*)

(defun load-program (str-vertex-shader str-fragment-shader)
  "Create program-data object from shader strings. Hardcoded uniform reference."
  (let ((shader-list (list))
	(data (make-instance 'program-data)))
    (push (arc:create-shader
	   :vertex-shader
	   (arc:file-to-string (merge-pathnames str-vertex-shader *glsl-directory*)))
	  shader-list)
    (push (arc:create-shader
	   :fragment-shader
	   (arc:file-to-string (merge-pathnames str-fragment-shader *glsl-directory*)))
    	  shader-list)
    (setf (the-program data) (arc:create-program shader-list))
    ;; hard-coding time: also this should undergo test if assignment was successful
    (setf (model-to-world-matrix-unif data)
	  (gl:get-uniform-location (the-program data) "model_to_world_matrix"))

    ;; stores a _uniform block index_ that is used to refer to a uniform block,
    ;; in this case a block that is supposed to store w-to-cam-mat4 and cam-to-clip-mat4
    (setf (global-uniform-block-index data)
	  ;; TODO: pull request to cl-opengl of (gl:get-uniform-block-index ...) !! :>
	  (cffi:with-foreign-string (s "global_matrices")
	    (%gl:get-uniform-block-index (the-program data) s)))

    ;; TODO: if uniform doesn't really exist in shader, wasn't opengl lenient about it?
    (setf (base-color-unif data)
	  (gl:get-uniform-location (the-program data) "base_color"))

    ;; This tells a program where in the opengl context the uniform-buffer can
    ;; be found. In this case it will find it in the handle stored in
    ;; *global-matrices-binding-index*
    (%gl:uniform-block-binding (the-program data) (global-uniform-block-index data)
			       *global-matrices-binding-index*)
    data))


(defvar *global-matrices-ubo*)
(defparameter *global-matrices-binding-index* 0)

(defun initialize-program ()
  (setf *uniform-color*
	(load-program "pos-only-world-transform-ubo.vert" "color-uniform.frag"))
  (setf *object-color*
  	(load-program "pos-color-world-transform-ubo.vert" "color-passthrough.frag"))
  (setf *uniform-color-tint*
  	(load-program "pos-color-world-transform-ubo.vert" "color-mult-uniform.frag"))

  ;; feeding the opengl context with the UBO data
  (setf *global-matrices-ubo* (first (gl:gen-buffers 1)))
  (gl:bind-buffer :uniform-buffer *global-matrices-ubo*)
  ;(gl:buffer-data :uniform-buffer :stream-draw (gl:hmm) )
  ;; for now better to not use convenience function, as we don't store the array needed
  ;; as a global (it will be provided ad-hoc through glutil:perspective and
  ;; (with-transform (matrix-stack) ...)    
  (%gl:buffer-data :uniform-buffer #|float*16*2=|# 128  ;;aka: size-of:mat4*2 
		   (cffi-sys:null-pointer) ; 'NULL' , not: :null or NIL
		   :stream-draw)
  (gl:bind-buffer :uniform-buffer 0)

  ;; now that the opengl program knows where to look for the uniform-buffer data
  ;; (gl:block-binding ..) provides a 'binding-point' *global-matrices-binding-index* that
  ;; tells the program where to look in the opengl context for it.  Now all we need to do
  ;; is to actually bind the uniform-buffer object using this binding-point.
  (%gl:bind-buffer-range :uniform-buffer *global-matrices-binding-index*
			 *global-matrices-ubo*
			 0	       ; where the uniform-blocks data supposed to beginn
			 #|size-of:mat4*2|# (* 64 2) ; and how big it is
			 )
  )


(defparameter *cone-mesh* nil)
(defparameter *cylinder-mesh* nil)
(defparameter *cube-tint-mesh* nil)
(defparameter *cube-color-mesh* nil)
(defparameter *plane-mesh* nil)

(defun init-meshes ()
  (setf *cone-mesh*
	(framework::xml->mesh-obj (merge-pathnames *data-dir* "UnitConeTint.xml")))
  (setf *cylinder-mesh*
	(framework::xml->mesh-obj (merge-pathnames *data-dir* "UnitCylinderTint.xml")))
  (setf *cube-tint-mesh*
	(framework::xml->mesh-obj (merge-pathnames *data-dir* "UnitCubeTint.xml")))
  (setf *cube-color-mesh*
	(framework::xml->mesh-obj (merge-pathnames *data-dir* "UnitCubeColor.xml")))
  (setf *plane-mesh*
	(framework::xml->mesh-obj (merge-pathnames *data-dir* "UnitPlane.xml"))))

(defun init ()
	(initialize-program)
	(init-meshes)

	;; TODO: why doesn't this seem to affect the unit-plane when it is rotated 360?
	;; this gotta be a pernicious bug, swapping the z-axis so that the winding order is
	;; always clock-wise?
	(gl:enable :cull-face)
	(%gl:cull-face :back)
	(%gl:front-face :cw) 

	(gl:viewport 0 0 500 500)

	(gl:enable :depth-test)
	(gl:depth-mask :true)
	(%gl:depth-func :lequal)
	(gl:depth-range 0.0 1.0)
)


;; makeshift solution
(defparameter t-mat (let ((translate-mat4 (glm:make-mat4 1.0))
			 (vec4 (glm:vec4-from-vec3 (glm:vec3 3.0 -5.0 -40.0))))
		     (glm:set-mat4-col translate-mat4 3 vec4)
		     translate-mat4))

;;g_ in arcsynthesis code variable names, is a convention for global-variable naming
;;hence replaced by ear-muffs
(defparameter *sphere-cam-rel-pos* (glm:vec3 67.5 -46.0 150.0) "Order: phi theta r")
(defparameter *cam-target* (glm:vec3 0.0 0.4 0.0))


(defun resolve-cam-position ()
  "Spherical coordinates stored in *sphere-cam-rel-pos* are transformed to Euclidean
geometry coordinates and returned as a position vector."
  (let* ((phi (framework:deg-to-rad (glm:vec. *sphere-cam-rel-pos* :x)))
	 (theta (framework:deg-to-rad (+ (glm:vec. *sphere-cam-rel-pos* :y)
					 90.0)))
	 (sin-theta (sin theta))
	 (cos-theta (cos theta))
	 (cos-phi (cos phi))
	 (sin-phi (sin phi))
	 ;; this is black magic, also called trigonometry: we effectively produce a
	 ;; euclideon vector out of polar coordinates cos-theta is the y
	 ;; shortened/reversed by theta given. Complementaryly sin-theta is the
	 ;; perpendicular x value, but since we need to move by phi, from there, we need
	 ;; to shorten/reverse the x value (sin-theta) by cos-phi, which we do by
	 ;; multiplying it with the cos-phi again complementarily we grow/reverse
	 ;; the perpendicular z. z, if phi is 0-degrees is equal to sin-phi (namely 0)
	 ;; but the moment it is not 0, we need to adjust it by multiplying it with
	 ;; its relative "host" axis which is sin-theta.
	 ;; To facilitate intuitive understanding I strongly recommend drawing it
	 ;; on paper trying to anticipate the relations. The same initial rules
	 ;; apply for any "nested" angles added.
	 (dir-to-camera (glm:vec3 (* sin-theta cos-phi)
	 			  cos-theta
	 			  (* sin-theta sin-phi))))
    ;; Once the direction is set, we need to blow it up by multiplying the
    ;; "euclidean" vector by 'r' which is the :z value of *sphere-cam-rel-pos*
    ;; and add it to the target the camera is supposed to look at, thereby creating
    ;; a geometrical dependent positions of the camera to the *cam-target*
    (sb-cga:vec+ (sb-cga:vec* dir-to-camera (glm:vec. *sphere-cam-rel-pos* :z))
		 *cam-target*)
    ))

;; Note: c++ function signature: foo(const &var) means:
;; &var we don't need a copy (reuse of resource;pass by reference)
;; and 'const' ensures we will not mutate it (save pass by reference for user
;; of this function). Also this probably helps the compiler.

;; (defparameter tc (lambda () (calc-look-at-matrix
;; 			     (glm:vec3 0.0 0.0 1.0) ;be
;; 			     (glm:vec3 0.0)         ;look at
;; 			     (glm:vec3 0.0 1.0 0.0)))) ;up

;; TODO: hm the resultin matrix from tc has many rounding problems
(defun calc-look-at-matrix (camera-pt look-pt up-pt)
  ;; camera-pt already is set relative to look-pt by being added to it in
  ;; resolve-cam-position. negating the two yields the direction of the camera "through"
  ;; look-pt. Unit vector, through normalize, is needed as we will use look-dir
  ;; directly as the axis of the look-at-matrix, so as to prevent scaling!
  ;; With this we already have our Z axis
  (let* ((look-dir (sb-cga:normalize (sb-cga:vec- look-pt camera-pt)))
	 ;; since we only want a direction, we normalize the vector
	 ;; using up-dir we have a plane from which we can yield the perpendicular x-axis
	 ;; and from that the perpendicular y-axis (cross-product z-axis x-axis)
	 (up-dir (sb-cga:normalize up-pt))
	 ;; cross-product returns the vector perpendicular to the plane formed
	 ;; by two vectors:
	 ;; (sb-cga:cross-product (glm:vec3 1.0 0.0 0.0) (glm:vec3 0.0 1.0 0.0))
	 ;; ==> #(0.0 0.0 1.0)	 
	 (right-dir (sb-cga:normalize (sb-cga:cross-product look-dir up-dir)))
	 (perp-up-dir (sb-cga:cross-product right-dir look-dir))

	 (rot-mat (glm:make-mat4 1.0))
	 (trans-mat (glm:make-mat4 1.0)))

    (glm:set-mat4-col rot-mat 0 (glm:vec4-from-vec3 right-dir 0.0))
    (glm:set-mat4-col rot-mat 1 (glm:vec4-from-vec3 perp-up-dir 0.0))
    ;; the look-dir must be negated, or it wouldn't be a rotation of the original
    ;; identity matrix. As it currently would be a transform that couldn't arise
    ;; from rotating the original coordinate system (one axis is moved without
    ;; moving another by _the same_ angle). This must be a problem that arises from
    ;; using the cross-product, which doesn't seem to return the perpendicular axis
    ;; needed (there are always two perpendicular direction vectors for a plane)
    (glm:set-mat4-col rot-mat 2 (glm:vec4-from-vec3 (glm:vec- look-dir) 0.0))

    ;; TODO: why transpose it eventually? Maybe because it is col-major and setting
    ;; column-wise and transpose is more efficient than just setting the rows
    ;; with discontiguous indices
    (setf rot-mat (sb-cga:transpose-matrix rot-mat))

    ;; oh, its just a translation matrix putting the camera-pt into origin! (and thereby
    ;; offsetting every position sent through this matrix by the camera pos
    (glm:set-mat4-col trans-mat 3 (glm:vec4-from-vec3 (glm:vec- camera-pt) 1.0))

    ;;return rotmat * transmat;
    (sb-cga:matrix* rot-mat trans-mat)))

(defun draw-look-at-point (model-matrix)
  ;; to draw the following on top regardless of any previously drawn objects, we
  ;; disable the depth-test momentarily
  (gl:disable :depth-test)
  ;; we use the as a translation, which is the one the camera is set up relative to,
  ;; to always look at.. ideal for our look-at-point. In the last program we bypassed
  ;; the world-to-camera-matrix (it was identity) we calculated a direction vector
  ;; from cam-pos to cam-target and used its negated length to translate the draw-point
  ;; negated because the perspective-divide set up by camera-to-clip-matrix wants
  ;; the -z-axis to be the one we look at, at all time.
  ;; This time around we can't bypass the world-to-cam matrix because of the UBO
  ;; setting both. Well we could but its a performance issue to set them here and
  ;; unset them afterwards.. so we use the cam-target to draw directly in front of the
  ;; camera, which cam-target is for in the first place. Now the difference to
  ;; the 'world-scene' program is that the look-at-cube will keep its orientation
  ;; as the camera moves around it, because we use the same model-matrix looking
  ;; at it from different world-to-cam->cam-to-world matrices, while in the last program
  ;; we skipped the world-to-cam matrix thereby forcing the model-space orientation
  ;; not being displayed relative to the world-to-cam-matrix 
  (let ((x (aref *cam-target* 0))
	(y (aref *cam-target* 1))
	(z (aref *cam-target* 2)))
    (glutil:with-transform (model-matrix)
	;;;:translate 0.0 1.0 (- (sb-cga:vec-length cam-aim-vec))
	:translate x y z
	:scale 1.0 1.0 1.0
	:rotate-y 20.0

	(gl:use-program (the-program *object-color*))
	(gl:uniform-matrix (model-to-world-matrix-unif *object-color*) 4
			   (vector (glutil:top-ms model-matrix)) NIL)
	;; (gl:uniform-matrix (world-to-camera-matrix-unif *object-color*) 4
	;; 		   (vector identity) NIL)
	(framework:render *cube-color-mesh*)
	(gl:use-program 0)))
  (gl:enable :depth-test))

(defun draw-tree (matrix-stack &optional (trunk-height 2.0) (cone-height 3.0))
  ;; Draw trunk
  (glutil:with-transform (matrix-stack)
      :scale 1.0 trunk-height 1.0
      :translate 0.0 0.5 0.0 ;; check out the z-fighting when y = 1.0 !
      ;; TODO: write with-program-data macro?
      (gl:use-program (the-program *uniform-color-tint*))
      (gl:uniform-matrix (model-to-world-matrix-unif *uniform-color-tint*) 4
      			 (vector (glutil:top-ms matrix-stack)) NIL)
      (%gl:uniform-4f (base-color-unif *uniform-color-tint*) 0.694 0.4 0.106 1.0)
      (framework:render *cylinder-mesh*)
      (gl:use-program 0))
  ;; Draw the treetop
  (glutil:with-transform (matrix-stack)
      :translate 0.0 trunk-height 0.0
      :scale 3.0 cone-height 3.0

      (gl:use-program (the-program *uniform-color-tint*))
      (gl:uniform-matrix (model-to-world-matrix-unif *uniform-color-tint*) 4
			 (vector (glutil:top-ms matrix-stack)) NIL)
      (%gl:uniform-4f (base-color-unif *uniform-color-tint*) 0.0 1.0 0.0 1.0)
      (framework:render *cone-mesh*)))

(defvar *tree-data*
  (apply #'vector
   (mapcar (lambda (x) (apply #'vector x))
	   '((-45.0 -40.0 2.0 3.0)
	     (-42.0 -35.0 2.0 3.0) 
	     (-39.0 -29.0 2.0 4.0) 
	     (-44.0 -26.0 3.0 3.0) 
	     (-40.0 -22.0 2.0 4.0) 
	     (-36.0 -15.0 3.0 3.0) 
	     (-41.0 -11.0 2.0 3.0) 
	     (-37.0 -6.0 3.0 3.0) 
	     (-45.0 0.0 2.0 3.0) 
	     (-39.0 4.0 3.0 4.0) 
	     (-36.0 8.0 2.0 3.0) 
	     (-44.0 13.0 3.0 3.0) 
	     (-42.0 17.0 2.0 3.0) 
	     (-38.0 23.0 3.0 4.0) 
	     (-41.0 27.0 2.0 3.0) 
	     (-39.0 32.0 3.0 3.0) 
	     (-44.0 37.0 3.0 4.0) 
	     (-36.0 42.0 2.0 3.0) 

	     (-32.0 -45.0 2.0 3.0) 
	     (-30.0 -42.0 2.0 4.0) 
	     (-34.0 -38.0 3.0 5.0) 
	     (-33.0 -35.0 3.0 4.0) 
	     (-29.0 -28.0 2.0 3.0) 
	     (-26.0 -25.0 3.0 5.0) 
	     (-35.0 -21.0 3.0 4.0) 
	     (-31.0 -17.0 3.0 3.0) 
	     (-28.0 -12.0 2.0 4.0) 
	     (-29.0 -7.0 3.0 3.0) 
	     (-26.0 -1.0 2.0 4.0) 
	     (-32.0 6.0 2.0 3.0) 
	     (-30.0 10.0 3.0 5.0) 
	     (-33.0 14.0 2.0 4.0) 
	     (-35.0 19.0 3.0 4.0) 
	     (-28.0 22.0 2.0 3.0) 
	     (-33.0 26.0 3.0 3.0) 
	     (-29.0 31.0 3.0 4.0) 
	     (-32.0 38.0 2.0 3.0) 
	     (-27.0 41.0 3.0 4.0) 
	     (-31.0 45.0 2.0 4.0) 
	     (-28.0 48.0 3.0 5.0) 

	     (-25.0 -48.0 2.0 3.0) 
	     (-20.0 -42.0 3.0 4.0) 
	     (-22.0 -39.0 2.0 3.0) 
	     (-19.0 -34.0 2.0 3.0) 
	     (-23.0 -30.0 3.0 4.0) 
	     (-24.0 -24.0 2.0 3.0) 
	     (-16.0 -21.0 2.0 3.0) 
	     (-17.0 -17.0 3.0 3.0) 
	     (-25.0 -13.0 2.0 4.0) 
	     (-23.0 -8.0 2.0 3.0) 
	     (-17.0 -2.0 3.0 3.0) 
	     (-16.0 1.0 2.0 3.0) 
	     (-19.0 4.0 3.0 3.0) 
	     (-22.0 8.0 2.0 4.0) 
	     (-21.0 14.0 2.0 3.0) 
	     (-16.0 19.0 2.0 3.0) 
	     (-23.0 24.0 3.0 3.0) 
	     (-18.0 28.0 2.0 4.0) 
	     (-24.0 31.0 2.0 3.0) 
	     (-20.0 36.0 2.0 3.0) 
	     (-22.0 41.0 3.0 3.0) 
	     (-21.0 45.0 2.0 3.0) 

	     (-12.0 -40.0 2.0 4.0) 
	     (-11.0 -35.0 3.0 3.0) 
	     (-10.0 -29.0 1.0 3.0) 
	     (-9.0 -26.0 2.0 2.0) 
	     (-6.0 -22.0 2.0 3.0) 
	     (-15.0 -15.0 1.0 3.0) 
	     (-8.0 -11.0 2.0 3.0) 
	     (-14.0 -6.0 2.0 4.0) 
	     (-12.0 0.0 2.0 3.0) 
	     (-7.0 4.0 2.0 2.0) 
	     (-13.0 8.0 2.0 2.0) 
	     (-9.0 13.0 1.0 3.0) 
	     (-13.0 17.0 3.0 4.0) 
	     (-6.0 23.0 2.0 3.0) 
	     (-12.0 27.0 1.0 2.0) 
	     (-8.0 32.0 2.0 3.0) 
	     (-10.0 37.0 3.0 3.0) 
	     (-11.0 42.0 2.0 2.0) 


	     (15.0 5.0 2.0 3.0) 
	     (15.0 10.0 2.0 3.0) 
	     (15.0 15.0 2.0 3.0) 
	     (15.0 20.0 2.0 3.0) 
	     (15.0 25.0 2.0 3.0) 
	     (15.0 30.0 2.0 3.0) 
	     (15.0 35.0 2.0 3.0) 
	     (15.0 40.0 2.0 3.0) 
	     (15.0 45.0 2.0 3.0) 

	     (25.0 5.0 2.0 3.0) 
	     (25.0 10.0 2.0 3.0) 
	     (25.0 15.0 2.0 3.0) 
	     (25.0 20.0 2.0 3.0) 
	     (25.0 25.0 2.0 3.0) 
	     (25.0 30.0 2.0 3.0) 
	     (25.0 35.0 2.0 3.0) 
	     (25.0 40.0 2.0 3.0) 
	     (25.0 45.0 2.0 3.0)))))

(defun draw-forest (matrix-stack)
  (loop for forest-data across *tree-data*
     for fx-pos = (aref forest-data 0)
     for fz-pos = (aref forest-data 1)
     for trunk-height = (aref forest-data 2)
     for cone-height = (aref forest-data 3)
     do
       (glutil:with-transform (matrix-stack)
	   :translate fx-pos 0.0 fz-pos
	   (draw-tree matrix-stack trunk-height cone-height))))

(defparameter *column-base-height* 0.25)

(defun draw-column (matrix-stack &optional (height 5.0))
  ;; Draw the bottom of the column
  (glutil:with-transform (matrix-stack)
;      (print (glutil:top-ms matrix-stack))
      :scale 1.0 *column-base-height* 1.0
;      :translate 0.0 0.5 0.0 ;; this is on purpose to prevent z-fighting?
      
      (gl:use-program (the-program *uniform-color-tint*))
      (gl:uniform-matrix (model-to-world-matrix-unif *uniform-color-tint*) 4
			 (vector (glutil:top-ms matrix-stack)) NIL)
      (%gl:uniform-4f (base-color-unif *uniform-color-tint*) 1.0 1.0 1.0 1.0)
      (framework:render *cube-tint-mesh*)
      (gl:use-program 0))
  ;; Draw the top of the column
  (glutil:with-transform (matrix-stack)
      :translate 0.0 (- height *column-base-height*) 0.0
      :scale 1.0 *column-base-height* 1.0
      ;; TODO: had to change from y = 0.5, maybe arc code is not up-to-date?
      :translate 0.0 -0.25 0.0
      (gl:use-program (the-program *uniform-color-tint*))
      (gl:uniform-matrix (model-to-world-matrix-unif *uniform-color-tint*) 4
			 (vector (glutil:top-ms matrix-stack)) NIL)
      (%gl:uniform-4f (base-color-unif *uniform-color-tint*) 0.9 0.9 0.9 0.9)
      (framework:render *cube-tint-mesh*)
      (gl:use-program 0))
  ;; Draw the main column ;; TODO: why does it draw it falsely
  (glutil:with-transform (matrix-stack)
      :translate 0.0 *column-base-height* 0.0
      :scale 0.8 (- height (* *column-base-height* 2.0)) 0.8
      ;; changed from y = 0.5
      :translate 0.0 2.0 0.0
      (gl:use-program (the-program *uniform-color-tint*))
      (gl:uniform-matrix (model-to-world-matrix-unif *uniform-color-tint*) 4
			 (vector (glutil:top-ms matrix-stack)) NIL)
      (%gl:uniform-4f (base-color-unif *uniform-color-tint*) 0.9 0.9 0.9 0.9)
      (framework:render *cylinder-mesh*)
      (gl:use-program 0)))

(defparameter *parthenon-width* 14.0)
(defparameter *parthenon-length* 20.0)
(defparameter *parthenon-column-height* 5.0)
(defparameter *parthenon-base-height* 1.0)
(defparameter *parthenon-top-height* 2.0)

(defun draw-parthenon (matrix-stack)
  ;; Draw base
  (glutil:with-transform (matrix-stack)
      :scale *parthenon-width* *parthenon-base-height* *parthenon-length*
      :translate 0.0 0.5 0.0

      (gl:use-program (the-program *uniform-color-tint*))
      (gl:uniform-matrix (model-to-world-matrix-unif *uniform-color-tint*) 4
			 (vector (glutil:top-ms matrix-stack)) NIL)
      (%gl:uniform-4f (base-color-unif *uniform-color-tint*) 0.9 0.9 0.9 0.9)
      (framework:render *cube-tint-mesh*)
      (gl:use-program 0))

  ;; Draw top
  (glutil:with-transform (matrix-stack)
      :translate 0.0 (+ *parthenon-column-height* *parthenon-base-height*) 0.0
      :scale *parthenon-width* *parthenon-top-height* *parthenon-length*
      :translate 0.0 0.5 0.0
      (gl:use-program (the-program *uniform-color-tint*))
      (gl:uniform-matrix (model-to-world-matrix-unif *uniform-color-tint*) 4
  			 (vector (glutil:top-ms matrix-stack)) NIL)
      (%gl:uniform-4f (base-color-unif *uniform-color-tint*) 0.9 0.9 0.9 0.9)
      (framework:render *cube-tint-mesh*)
      (gl:use-program 0))

  ;; Draw columns
  (let ((f-front-z-val (1- (/ *parthenon-length* 2.0)))
	(f-right-x-val (1- (/ *parthenon-width* 2.0))))
    (loop for i-col-num below (/ *parthenon-width* 2.0) do
	 (glutil:with-transform (matrix-stack)
	     :translate (1+ (- (* i-col-num 2.0) (/ *parthenon-width* 2.0)))
	     *parthenon-base-height* f-front-z-val
	     (draw-column matrix-stack *parthenon-column-height*))
	 (glutil:with-transform (matrix-stack)
	     :translate (1+ (- (* 2.0 i-col-num) (/ *parthenon-width* 2.0)))
	     *parthenon-base-height* (- f-front-z-val)
	     (draw-column matrix-stack *parthenon-column-height*)))

    ;; Don't draw the first or last columns, since they've been drawn already
    (loop for i-col-num from 1 below (/ (- *parthenon-length* 2.0) 2.0) do
	 (glutil:with-transform (matrix-stack)
	     :translate f-right-x-val *parthenon-base-height*
	     (1+ (- (* 2.0 i-col-num) (/ *parthenon-length* 2.0)))
	     (draw-column matrix-stack *parthenon-column-height*))
	 (glutil:with-transform (matrix-stack)
	     :translate (- f-right-x-val) *parthenon-base-height*
	     (1+ (- (* 2.0 i-col-num) (/ *parthenon-length* 2.0)))
	     (draw-column matrix-stack *parthenon-column-height*))))

  ;; Draw interior
  (glutil:with-transform (matrix-stack)
      :translate 0.0 1.0 0.0
      :scale (- *parthenon-width* 6.0) *parthenon-column-height*
      (- *parthenon-length* 6.0)
      ;; changed from y = 0.5
      :translate 0.0 1.5 0.0
      ;; secret-cube :>
      (gl:use-program (the-program *object-color*))
      (gl:uniform-matrix (model-to-world-matrix-unif *object-color*) 4
			 (vector (glutil:top-ms matrix-stack)) NIL)
      (framework:render *cube-color-mesh*)
      (gl:use-program 0))
    
  ;; Draw headpiece
  (glutil:with-transform (matrix-stack)
      :translate 0.0
      (- (+ *parthenon-column-height* *parthenon-base-height*
	    (/ *parthenon-top-height* 2.0)) 0.5)
      (/ *parthenon-length* 2.0)
      :rotate-x -135.0
      :rotate-y 45.0
      (gl:use-program (the-program *object-color*))
      (gl:uniform-matrix (model-to-world-matrix-unif *object-color*) 4
			 (vector (glutil:top-ms matrix-stack)) NIL)
      (framework:render *cube-color-mesh*)
      (gl:use-program 0))
    
  )

(defparameter *look-pt* (glm:vec3 0.0 0.0 0.0)) ; look at actual vertex of drawn object
(defparameter *cam-pt* (glm:vec3 0.0 0.0 1.0))
(defparameter *draw-look-at-point* nil)

(defun draw ()
  (let ((cam-pos (resolve-cam-position))
	(cam-matrix (make-instance 'glutil:matrix-stack))
	(model-matrix (make-instance 'glutil:matrix-stack)))

    (glutil:set-matrix cam-matrix
		       (calc-look-at-matrix cam-pos *cam-target* (glm:vec3 0.0 1.0 0.0)))
    ;; set world-to-camera matrix in UBO!
    (gl:bind-buffer :uniform-buffer *global-matrices-ubo*)
    (gl:buffer-sub-data :uniform-buffer
    			(arc:create-gl-array-from-vector (glutil:top-ms cam-matrix))
    			;; since it's the 2nd matrix we :buffer-offset at
			;; 64='mat4 size in bytes'
    			:buffer-offset 64)
    (gl:bind-buffer :uniform-buffer 0)

    ;; TODO: all the other camera-matrices setting

    ;; render the ground plane:
    (glutil:with-transform (model-matrix)
	:scale 100.0 1.0 100.0

	;; TODO fold into WITH-TRANSFORM macro: optional slots (make matrix-stack
	;; have slots for shader uniforms? Create shader-program class to work with?

	(%gl:use-program (the-program *uniform-color*))
	(gl:uniform-matrix (model-to-world-matrix-unif *uniform-color*) 4
			   (vector (glutil:top-ms model-matrix)) NIL)
	;; TODO: noo, something is off. The colors looks different.. uglier too
	(%gl:uniform-4f (base-color-unif *uniform-color*) 0.302 0.416 0.0589 1.0)
	(framework:render *plane-mesh*)
	;; (gl:use-program (the-program *uniform-color-tint*))
	;; :scale 1.0 50.0 1.0
	;; (gl:uniform-matrix (model-to-world-matrix-unif *uniform-color-tint*) 4
	;; 		   (vector (glutil:top-ms model-matrix)) NIL)
	;; (framework:render *cone-mesh*)
	;; (gl:use-program 0)
	) 
    ;; now that arc codes has onle "PUSH-MS" while here we use WITH-TRANSFORM
    ;; this works for arc because it uses separate namespaces { inside these }
    ;; model-matrix { push matrix-stack } code outside the curly-brackets refers to
    ;; model-matrix as if the code inside the {brackets} never happened!
    ;;Draw the trees:

   (draw-forest model-matrix)

    ;;draw building
    (glutil:with-transform (model-matrix)
	:translate 20.0 0.0 -10.0
	(draw-parthenon model-matrix)
	)

    (when *draw-look-at-point*
      (draw-look-at-point model-matrix))

    ))


(defun display ()
  (gl:clear-color 0.0 0.0 0.2 1)
  (gl:clear-depth 1.0)
  (gl:clear :color-buffer-bit :depth-buffer-bit)


  (draw)
  
  ;;swap buffers: in main loop 
       )

(defparameter *fz-near* 1.0)
(defparameter *fz-far* 1000.0)

(defun reshape (w h)
  ;; for now where we set the camera-to-clip perspective-matrix for the shaders
  (let ((pers-matrix (make-instance 'glutil:matrix-stack)))
    (glutil:perspective pers-matrix 45.0 (/ w h) *fz-near* *fz-far*)
    ;; set camera-matrix, note this starts writing at the default offset=0, and it writes one perspective
    ;; matrix into the uniform-buffer. The uniform buffer-block in the shader program starts hence
    ;; with the mat4 camaera_to_clip_matrix;
    (gl:bind-buffer :uniform-buffer *global-matrices-ubo*)
    (gl:buffer-sub-data :uniform-buffer
			(arc:create-gl-array-from-vector (glutil:top-ms pers-matrix)))
    (gl:bind-buffer :uniform-buffer 0))
  (%gl:viewport 0 0 w h))

(defun main ()
  (sdl2:with-init (:everything)
    (progn (setf *standard-output* out) (setf *debug-io* dbg) (setf *error-output* err))
    (sdl2:with-window (win :w 500 :h 500 :flags '(:shown :opengl :resizable))
      (sdl2:with-gl-context (gl-context win)
	;; INIT code:
	(init)
	;; TODO: callback for reshape; for now used to setup cam-to-clip-space matrix
	(reshape 500.0 500.0)
	(sdl2:with-event-loop (:method :poll)
	  (:keydown
	   (:keysym keysym)
	   ;; TODO: capture in macro
	   ;; move cam target horizontally
	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-a)
	     (decf (glm:vec. *cam-target* :x) 0.4))
	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-d)
	     (incf (glm:vec. *cam-target* :x) 0.4))
	   ;; move cam target vertically 
	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-w)
	     (decf (glm:vec. *cam-target* :z) 0.4))
	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-s)
	     (incf (glm:vec. *cam-target* :z) 0.4))
	   ;; move camera target up/down
	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-e)
	     (decf (glm:vec. *cam-target* :y) 4.0))
   	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-q)
	     (incf (glm:vec. *cam-target* :y) 4.0))
	   ;; rotate camera horizontally around target
	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-j)
	     (decf (glm:vec. *sphere-cam-rel-pos* :x) 1.125))
   	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-l)
	     (incf (glm:vec. *sphere-cam-rel-pos* :x) 1.125))
	   ;; rotate cam vertically around target
   	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-i)
	     (decf (glm:vec. *sphere-cam-rel-pos* :y) 1.125))
   	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-k)
	     (incf (glm:vec. *sphere-cam-rel-pos* :y) 1.125))
	   ;; zoom camera in/out of target
      	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-u)
	     (decf (glm:vec. *sphere-cam-rel-pos* :z) 1.5))
   	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-o)
	     (incf (glm:vec. *sphere-cam-rel-pos* :z) 1.5))

	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-space)
	     (if *draw-look-at-point*
		 (setf *draw-look-at-point* nil)
		 (setf *draw-look-at-point* t)))

	   (when (sdl2:scancode= (sdl2:scancode-value keysym) :scancode-escape)
	     (sdl2:push-event :quit)))
	  (:quit () t)
	  (:idle ()
		 ;; preventing special cases:
		 (setf (glm:vec. *sphere-cam-rel-pos* :y)
		       (glm:clamp (glm:vec. *sphere-cam-rel-pos* :y) -78.75 1.0))
		 (setf (glm:vec. *cam-target* :y)
		       (if (> (glm:vec. *cam-target* :y) 0.0)
			   (glm:vec. *cam-target* :y)
			   0.0))
		 ;; can't zoom in "through" the floor
		 (setf (glm:vec. *sphere-cam-rel-pos* :z)
		       (if (> (glm:vec. *sphere-cam-rel-pos* :z) 5.0)
		 	   (glm:vec. *sphere-cam-rel-pos* :z)
		 	   5.0))		 
		 ;;main-loop:
		 (display)
		 
                 (sdl2:gl-swap-window win) ; wow, this can be forgotten easily -.-
		 ))))))

