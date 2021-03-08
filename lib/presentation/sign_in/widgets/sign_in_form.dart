import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:another_flushbar/flushbar_helper.dart';
import 'package:auto_route/auto_route.dart';

import 'package:highlights/application/authentication/auth_bloc.dart';
import 'package:highlights/application/authentication/sign_in_form/sign_in_form_bloc.dart';
import 'package:highlights/presentation/routes/router.gr.dart';

class SignInForm extends StatelessWidget {
  /// This property must be `static` to avoid build loop
  ///
  /// See https://github.com/flutter/flutter/issues/20042
  ///
  // ignore: prefer_final_fields
  static GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  // Quitar el "final" parece prevenir un error al cerrar sesión y volver al sign in, pero no está claro cómo o por qué

  // TODO: update tests
  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            // TODO: little improvement: replace any "map"/"maybeMap" with
            // "when"/"maybeWhen" to get destructuring
            state.maybeWhen(
              emailVerificationSent: () {
                FlushbarHelper.createInformation(
                  message: 'Check your inbox to verify your account',
                ).show(context);
              },
              emailVerified: () {
                ExtendedNavigator.of(context)
                    .replace(Routes.highlightOverviewPage);

                context
                    .read<AuthBloc>()
                    .add(const AuthEvent.authCheckRequested());
              },
              emailVerificationFailed: (failure) {
                failure.maybeWhen(
                  tooManyRequests: () {
                    FlushbarHelper.createError(
                      message: 'Wait a few seconds before submitting again',
                    ).show(context);
                  },
                  serverError: () {
                    FlushbarHelper.createError(
                      message: 'Server Error',
                    ).show(context);
                  },
                  orElse: () {},
                );
              },
              orElse: () {},
            );
          },
        ),
        BlocListener<SignInFormBloc, SignInFormState>(
          listener: (context, state) {
            // Fold Option keeping possible failures and show notification in
            // case one is encountered
            state.authFailureOrSuccessOption.fold(
              // Do nothing when authFailureOrSuccessOption is none(), becuase
              // that means that nothing has happened yet
              () {},
              (failureOrUnit) => failureOrUnit.fold(
                (failure) {
                  FlushbarHelper.createError(
                    message: failure.map(
                      networkConnectionFailed: (_) =>
                          'Network connection failed. Check you internet status',
                      cancelledByUser: (_) => 'Cancelled',
                      serverError: (_) => 'Server Error',
                      invalidEmailAndPasswordCombination: (_) =>
                          'Invalid email and password combination',
                      emailAlreadyInUse: (_) => 'Email already in use',
                      tooManyRequests: (_) =>
                          'Wait a few seconds before submitting again',

                      // TODO: remove this handler and treat it as 'server error'
                      operationNotAllowed: (_) =>
                          'User blocked 🚫 Contact support',
                    ),
                  ).show(context);
                },
                (_) {
                  context
                      .read<AuthBloc>()
                      .add(const AuthEvent.emailVerificationRequested());
                },
              ),
            );
          },
        ),
      ],
      child: BlocBuilder<SignInFormBloc, SignInFormState>(
        builder: (context, state) {
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                const Icon(
                  Icons.format_quote,
                  size: 130,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('email_field'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.email),
                    labelText: 'Email',
                  ),
                  autocorrect: false,
                  onChanged: (value) {
                    context
                        .read<SignInFormBloc>()
                        .add(SignInFormEvent.emailChanged(value));
                  },

                  // Use state from bloc instead of buildder method,
                  // because latter is delayed (it'll validate the
                  // previous state instead of the current text inputed)
                  validator: (_) => context
                      .read<SignInFormBloc>()
                      .state
                      .emailAddress
                      .value
                      .fold(
                        (failure) => failure.maybeMap(
                          invalidEmail: (_) => 'Invalid Email',
                          orElse: () => null,
                        ),
                        // If validator returns null, then any feedback is
                        // provided to user because everithing is right
                        (_) => null,
                      ),

                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('password_field'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock),
                    labelText: 'Password',
                  ),
                  autocorrect: false,
                  obscureText: true,
                  onChanged: (value) {
                    context
                        .read<SignInFormBloc>()
                        .add(SignInFormEvent.passwordChanged(value));
                  },
                  validator: (_) => context
                      .read<SignInFormBloc>()
                      .state
                      .password
                      .value
                      .fold(
                          (failure) => failure.maybeMap(
                              shortPassword: (_) => 'Short Password',
                              orElse: () => null),
                          (_) => null),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        key: const Key('sign_in_button'),
                        onPressed: () {
                          // Trigger validation to display possible error messages
                          _formKey.currentState.validate();

                          context.read<SignInFormBloc>().add(
                              const SignInFormEvent
                                  .sigInWithEmailAndPasswordPessed());
                        },
                        child: const Text('SIGN IN'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        key: const Key('register_button'),
                        onPressed: () {
                          _formKey.currentState.validate();
                          context.read<SignInFormBloc>().add(
                              const SignInFormEvent
                                  .registerWithEmailAndPasswordPessed());
                        },
                        child: const Text('REGISTER'),
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: () {
                    context
                        .read<SignInFormBloc>()
                        .add(const SignInFormEvent.sigInWithGooglePessed());
                  },
                  child: const Text(
                    'SIGN IN WITH GOOGLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (state.isSubmitting) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ]
              ],
            ),
          );
        },
      ),
    );
  }
}
