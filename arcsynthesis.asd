;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-

(in-package :asdf-user)

(defsystem #:arcsynthesis
  :description "Modern OpenGL example code from the book 'Learning Modern 3D Graphics
Programming' by Jason L. McKesson (website:'www.arcsynthesis.org/gltut') ported to Common
Lisp (SBCL) using cl-sdl2 and cl-opengl"
  :version "0.0.1"
  :author "k-stz"
  :licence "MIT"
  :depends-on (:cl-opengl :sdl2 :sb-cga :cxml :cxml-stp)
  :serial t		  ; now: :file order in :components order is also dependency order
  :components
  ((:file "package")
   (:file "auxiliary-functions")
   (:file "glm")
   (:file "glutil")
   (:file "framework")
   ;; ":module" solves the "src in subdirectories" problem nicely!
   (:module "1-chapter/"
   	    :components ((:file "hello-triangle")))
   (:module "2-chapter/"
	    :components ((:file "frag-position")
			 (:file "vertex-colors")))
   (:module "3-chapter/"
   	    :components ((:file "cpu-position-offset")
   			 (:file "vert-calc-offset")
   			 (:file "vert-position-offset")
			 (:file "frag-change-color")))
   (:module "4-chapter"
	    :components ((:file "ortho-cube")
			 (:file "shader-perspective")
			 (:file "matrix-perspective")
			 (:file "aspect-ratio")))
   (:module "5-chapter"
	    :components ((:file "overlap-no-depth")
			 (:file "base-vertex-overlap")
			 (:file "depth-buffer")
			 (:file "vertex-clipping")
			 (:file "depth-clamping")))
   (:module "6-chapter"
	    :components ((:file "translation")
			 (:file "scale")
			 (:file "rotations")
			 (:file "hierarchy")))
   (:module "7-chapter"
	    :components ((:file "world-scene")
			 (:file "world-with-ubo")))
   (:module "8-chapter"
	    :components ((:file "gimbal-lock")
			 (:file "quaternion-YPR")
			 (:file "camera-relative")
			 (:file "interpolation")))
   (:module "9-chapter"
	    :components ((:file "basic-lighting")
			 (:file "scale-and-lighting")
			 (:file "ambient-lighting")))
   (:module "10-chapter"
	    :components ((:file "vertex-point-lighting")
			 (:file "fragment-point-lighting")
			 (:file "fragment-attenuation")))
   (:module "11-chapter"
	    :components ((:file "phong-lighting")
			 (:file "blinn-vs-phong-lighting")
			 (:file "gaussian-specular-lighting")))
   (:module "12-chapter"
	    :components ((:file "scene")
			 (:file "lights")
			 (:file "scene-lighting")))))
